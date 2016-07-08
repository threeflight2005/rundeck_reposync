#!/bin/bash

#set default project
PROJECT="TEST"

#set default endpoint, and port
api_endpoint=$(hostname)
api_port="4440"

#set working location
working_location="/home/rundeck/jobs/rundeck-jobs"

#set repo and branch
repository="git repo to sync from"
relative_repository="origin"
repository_branch="master"

##############################################################################


function repo_sync() {

	cd $working_location

	current_revision=$(git ls-remote $repository "HEAD" |  awk '{print $1}')
	latest_revision=$(git rev-parse "$relative_repository/$repository_branch")

	if [[ $latest_revision != $current_revision ]]; then

		git fetch --all >&2
		git reset --hard "$relative_repository/$repository_branch"
	else
		echo "Repo is current at $relative_repository/$repository_branch"
	fi
}


function job_import() {

	cd $working_location

	yaml_jobs=( $(find /home/rundeck/jobs/rundeck-jobs/ -name "*.yml") )
	xml_jobs=( $(find /home/rundeck/jobs/rundeck-jobs/ -name "*.xml") )

	if [ ${#yaml_jobs[@]} -gt 0 ]; then
		for i in /home/rundeck/jobs/rundeck-jobs/*.yml; do
			rd-jobs load -p $PROJECT --file "$i" -d update -F yaml
		done;
	fi

	if [ ${#xml_jobs[@]} -gt 0 ]; then
		for i in /home/rundeck/jobs/rundeck-jobs/*.xml; do
			rd-jobs load -p $PROJECT --file "$i" -d update -F xml
		done;
	fi

}


function job_remove() {

	cd $working_location

	yaml_jobs=( $(find /home/rundeck/jobs/rundeck-jobs/ -name "*.yml") )
	xml_jobs=( $(find /home/rundeck/jobs/rundeck-jobs/ -name "*.xml") )

	if [[ $repository_branch == "Dev" ]]; then
		localjobs=( $(curl -v -k -H "X-Rundeck-Auth-Token: $admin_api_key" -X GET https://$api_endpoint:$api_port/api/17/project/$PROJECT/jobs/export?format=yaml | sed -n -e 's/^.*uuid: //p') )
	else
		localjobs=( $(curl -v -H "X-Rundeck-Auth-Token: $admin_api_key" -X GET http://$api_endpoint:$api_port/api/17/project/$PROJECT/jobs/export?format=yaml | sed -n -e 's/^.*uuid: //p') )
	fi

	yaml_jobs_array=( $(for h in "${yaml_jobs[@]}"; do sed -n -e 's/^.*uuid: //p' "$h"; done;) )
	xml_jobs_array=( $(for h in "${xml_jobs[@]}"; do grep -oPm1 "(?<=<uuid>)[^<]+" "$h"; done;) )

	for i in "${localjobs[@]}"; do
		if [[ ${yaml_jobs_array[@]} =~ $i ]]; then
			echo "Job: " $i " exists."
		elif [[ ${xml_jobs_array[@]} =~ $i ]]; then
			echo "Job: " $i " exists."
		else
			echo "Job: " $i " Does not exist, REMOVING"
			rd-jobs purge -p $PROJECT -i $i
		fi
	done;
}

####################################################################

usage="$(basename "$0") [-h] [-prblaenwSIR] -- repo_sync.sh sync Rundeck job configurations from rundeck-jobs on stash

where:
-h  show this help text
-p  set the rundeck project (default: TEST)
-r  set the repoistory URL  (default: ssh://git@stash.softlayer.local:7999/devops/rundeck-jobs.git)
-b  set the repository branch (default: master)
-l  set the relative repository (default: origin)
-a  set rundeck admin api key (required)
-e  set rundeck api endpoint (default: hostname)
-n  set api port  (default: 4440)
-w  set working location for repo storage and job import (default: /home/rundeck/jobs/rundeck-jobs)
-S  call sync git repo function
-I  call job import function
-R  call job remove function"

while getopts ':hp:r:b:l:a:e:n:w:SIR' option; do
	case "$option" in
		h) echo "$usage"
		exit
		;;
		p) PROJECT="$OPTARG"
		;;
		r) repository="$OPTARG"
		;;
		b) repository_branch="$OPTARG"
		;;
		l) relative_repository="$OPTARG"
		;;
		a) admin_api_key="$OPTARG"
		;;
		e) api_endpoint="$OPTARG"
		;;
		n) api_port="$OPTARG"
		;;
		w) working_location="$OPTARG"
		;;
		S) repo_sync
		;;
		I) job_import
		;;
		R) job_remove
		;;
		:) printf "missing argument for -%s\n" "$OPTARG" >&2
		echo "$usage" >&2
		exit 1
		;;
		\?) printf "illegal option: -%s\n" "$OPTARG" >&2
		echo "$usage" >&2
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))


if [ -z ${admin_api_key+x} ] ; then
	echo "api key is required"
	exit 1
else
	if [ $(cd $working_location && git rev-parse --git-dir) > /dev/null 2>&1  ]; then
		echo "Valid GIT Repo found at $working_location"
	else
		echo "Error: $working_location not a git repository"
		exit 1
	fi
fi

####################################################################
