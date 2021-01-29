#!/bin/bash
#
# A script to migrate gitolite repositories to gitlab.
#
# Downloads the repository list from the `gitolite-admin` repository and mirrors all repositories to a gitlab host
# under a given user as a private repo.
#
# https://github.com/rndstr/gitolite-to-gitlab

usage () {
    exec 4<&1
    exec 1>&2
    echo "usage: $(basename $0) [-i] <gitolite-admin-uri> <gitlab-url> <gitlab-user> <gitlab-token>"
    echo
    echo "  -i  Confirm each repository to migrate"
    echo "  -h  Display this help"
    echo
    echo "  gitolite-uri        Repository URI for the gitolite server (e.g., gitolite@example.com)"
    echo "  gitlab-url          Where your GitLab is hosted (e.g., https://www.gitlab.com)"
    echo "  gitlab-user         Username for which the projects should be created"
    echo "  gitlab-token        Private token for the API to create the projects (see https://www.gitlab.com/profile/account)"
    exec 1<&4
}

log () {
    echo -e "\e[0;33m>>> $*\e[0m"
}

success () {
    echo -e "\e[0;32m>>> $*\e[0m"
}

error () {
    echo -e "\e[0;31mERROR: $*\e[0m" 1>&2
}

get_gitlab_namespace_id() {
  namespace_id=$(curl --silent --header "PRIVATE-TOKEN: ${gitlab_token}" "${gitlab_url}/api/v4/namespaces?search=${gitlab_user}" |jq '.[].id')
  echo "${namespace_id}"
  if [[ "${namespace_id}" == *'400'* || ${namespace_id} == "" ]]; then
    log "ERROR: could not find user or group '${gitlab_user}' on GitLab server"
    exit 2
  fi
}

clone_repo () {
    lite_repo=${1}; lab_repo=${2}

    target=${cwd}/tmp/${lab_repo}
    repo_uri=${gitolite_uri}:${lite_repo}.git

    if [ -d ${target} ]; then
        log "${lite_repo}: found"
    else
        log "${lite_repo}@gitolite: download from ${repo_uri}"
        set +e
        git clone --mirror ${repo_uri} ${target}
        if [ $? -eq 1 ]; then
            # cleanup
            rm -r ${target}
            exit 1
        fi
        set -e
    fi
}

create_repo () {
    lite_repo=$1; lab_repo=$2

    log "${lite_repo}@gitlab: create project ${gitlab_url}/${gitlab_user}/${lab_repo}"

    set +e

    # Attempt to create repo on gitlab server
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --header "PRIVATE-TOKEN: ${gitlab_token}" "${gitlab_url}/api/v4/projects" --data "name=${lab_repo}&path=${lab_repo}&namespace_id=${namespace_id}")
    if [[ ${http_code} == "401" ]]; then
        log "${lite_repo}@gitlab: could not authenticate to gitlab API'"
        return 401
    fi

    if [[ ${http_code} != "201" ]]; then
        log "${lite_repo}@gitlab: could not create gitlab repo '${lab_repo}' for gitolite repo '${lite_repo}'. Got ${http_code} HTTP return code from gitlab"
        return 1
    fi
    set -e
    return 0
}

push_repo () {
    lite_repo=$1; lab_repo=$2

    lab_uri=git@${gitlab_domain}:${gitlab_user}/${lab_repo}.git
    log "${lite_repo}@gitlab: upload to ${lab_uri}"

    cd ${cwd}/tmp/${lab_repo}
    git push --mirror ${lab_uri}

    if ($? == 0); then
      success "${lite_repo}: migrated"
      return 0
    else
      error "Could not push ${lite_repo} to gitlab"
      return 1
    fi
}

clean_repo () {
    lab_repo=$1
    test -z ${lab_repo} && { error "this doesn't seem right, repo is empty; bailing"; exit 1; }
    cd ${cwd}
    rm -rf ${cwd}/tmp/${lab_repo}
    touch ${cwd}/tmp/${lab_repo}-migrated
}


interactive=0
while getopts hi name; do
    case ${name} in
        i) interactive=1;;
        h) usage; exit 1;;
        \?) usage; exit 2;;
    esac
done
shift $((OPTIND-1))

if [ $# -ne 4 ]; then
    error "missing arguments"
    usage
    exit 2
fi


gitolite_uri=$1
gitlab_url=$2
gitlab_user=$3
gitlab_token=$4
gitlab_domain=${gitlab_url##*//}


if [[ ! $gitlab_url == *"//"* ]]; then
    error "<gitlab-url> must contain a protocol"
    usage
    exit 2
fi

namespace_id=-1
log "gitlab: resolving ${gitlab_user} to namespace ID"
get_gitlab_namespace_id
log "gitlab: namespace ID resolved to ${namespace_id}"

# create a tmp directory
cwd=$(cd $(dirname $0); pwd)
mkdir "$cwd/tmp" 2>/dev/null

# get repository list
set -e
log "gitolite: retrieving repo list"
repos=$(ssh ${gitolite_uri} info -json |jq '.repos' |jq -r 'keys[]')

# migrate repositories
count=$(set -- ${repos}; echo $#)
index=0
for lite_repo in ${repos}; do
    ((++index))
    if [ ${interactive} -eq 1 ]; then
        read -p "Do you want to migrate repo '${lite_repo}'? [Yn] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            continue
        fi
    fi

    log "(${index}/${count}) ${lite_repo}"

    lab_repo=${lite_repo}
    if [[ ! ${lab_repo} =~ ^[a-zA-Z0-9_\.-]+$ ]]; then
        log "${lite_repo}: invalid characters in gitolite name, replacing them with dash for gitlab"
        lab_repo=$(echo ${lite_repo} | sed 's/[^a-zA-Z0-9_\.-]/-/g')
    fi

    if [ -f ${cwd}/tmp/${lab_repo}-migrated ]; then
        success "${lite_repo}: already migrated"
        continue
    fi

    clone_repo ${lite_repo} ${lab_repo} || continue
    create_repo ${lite_repo} ${lab_repo} || continue
    push_repo ${lite_repo} ${lab_repo} || continue
    clean_repo ${lab_repo}
done
