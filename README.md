# gitolite-to-gitlab

A script to migrate gitolite repositories to gitlab.

Downloads the repository list from the `gitolite-admin` repository and mirrors all repositories to a gitlab host
under a given user as a private repo.

## Prerequisites

* You may need to install Perl JSON module (`libjson-perl` package on debian) on the gitolite server in order to use this.
* You need `jq` locally installed
* Create an impersonation token on gitlab on a user with sufficient rights to create repositories

## Usage

```
gitolite-to-gitlab.sh [-i] [-h] <gitolite-admin-uri> <gitlab-url> <gitlab-user> <gitlab-token>

    -i  Confirm each repository to migrate
    -h  Display this help

    gitolite-admin-uri  Repository URI for the gitolite-admin repo (e.g., gitolite@example.com)
    gitlab-url          Where your GitLab is hosted (e.g., https://www.gitlab.com)
    gitlab-user         Username for which the projects should be created
    gitlab-token        Private token for the API to create the projects (see https://www.gitlab.com/profile/account)
```

If for some reason the migration process aborts (when a command fails) you can just restart and it will continue
where it left off.

