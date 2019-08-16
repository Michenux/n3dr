#!/bin/bash -ex

NEXUS_VERSION=$1
NEXUS_API_VERSION=$2
TOOL=$3

validate(){
    if [ -z "$TOOL" ]; then
        echo "No deliverable defined. Assuming that 'go run main.go' 
should be run."
        TOOL="go run main.go"
    fi

    if [ -z "$NEXUS_VERSION" ] || [ -z "$NEXUS_API_VERSION" ]; then
        echo "NEXUS_VERSION and NEXUS_API_VERSION should be specified."
        exit 1
    fi
}

nexus(){
    docker run -d -p 9999:8081 --name nexus sonatype/nexus3:${NEXUS_VERSION}
}

readiness(){
    until docker logs nexus | grep 'Started Sonatype Nexus OSS'
    do
        echo "Nexus unavailable"
        sleep 10
    done
}

# Since nexus 3.17.0 the default 'admin123' was changed by an autogenerated
# one. This function retrieves the autogenerated password and if this file
# is unavailable, the default 'admin123' is returned.
password(){
    if docker exec -it nexus cat /nexus-data/admin.password; then
        export PASSWORD=$(docker exec -it nexus cat /nexus-data/admin.password)
    else
        export PASSWORD="admin123"
    fi
}

upload(){
    echo "Testing upload..."
    $TOOL upload -u admin -p $PASSWORD -r maven-releases -n http://localhost:9999 -v ${NEXUS_API_VERSION}
    echo
}

backup(){
    echo "Testing backup..."
    $TOOL backup -n http://localhost:9999 -u admin -p $PASSWORD -r maven-releases -v ${NEXUS_API_VERSION}
    $TOOL backup -n http://localhost:9999 -u admin -p $PASSWORD -r maven-releases -v ${NEXUS_API_VERSION} -z

    if [ "${NEXUS_VERSION}" == "3.9.0" ]; then
        count_downloads 15
        test_zip 12
    else
        count_downloads 63
        test_zip 24
    fi

    cleanup_downloads
}

repositories(){
    echo "Testing repositories..."
    $TOOL repositories -n http://localhost:9999 -u admin -p $PASSWORD -v ${NEXUS_API_VERSION} -a | grep maven-releases
    $TOOL repositories -n http://localhost:9999 -u admin -p $PASSWORD -v ${NEXUS_API_VERSION} -c | grep 7
    $TOOL repositories -n http://localhost:9999 -u admin -p $PASSWORD -v ${NEXUS_API_VERSION} -b
    $TOOL repositories -n http://localhost:9999 -u admin -p $PASSWORD -v ${NEXUS_API_VERSION} -b -z

    if [ "${NEXUS_VERSION}" == "3.9.0" ]; then
        count_downloads 30
        test_zip 20
    else
        count_downloads 126
        test_zip 48
    fi

    cleanup_downloads
}

cleanup(){
    cleanup_downloads
    docker stop nexus
    docker rm nexus
}

count_downloads(){
    find download -type f | wc -l | grep $1
}

test_zip(){
    du -h test*zip | grep ${1}K
}

cleanup_downloads(){
    rm -f test*zip
    rm -rf download
}

main(){
    trap cleanup EXIT
    validate
    nexus
    readiness
    password
    upload
    backup
    repositories
}

main