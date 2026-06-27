git filter-branch -f --env-filter "
    GIT_AUTHOR_NAME='YRJ'
    GIT_AUTHOR_EMAIL='yeryindra@gmail.com'
    GIT_COMMITTER_NAME='YRJ'
    GIT_COMMITTER_EMAIL='yeryindra@gmail.com'
" HEAD

git push origin master --force
