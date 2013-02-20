# .bash_profile
# 2013-02-17.02.16.22
# Catalunya EPG@TID.ES 
# epgbcn4@tid.es aka seikath@gmail.com 

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
	. ~/.bashrc
fi

# User specific environment and startup programs

PATH=$PATH:$HOME/bin

export PATH
# export PS1="\u@\H:[\d \t]:[\w]\$ " 
export KBUILD_NOPEDANTIC=1 
export LDFLAGS=-ldl 
export HISTSIZE=55000 
export HISTTIMEFORMAT="%F %T " 
export MYSQL_PS1="mysql\_\u@$HOSTNAME:[\D][\d]>\_"

# de Eric Van Silverbergen http://www.linkedin.com/pub/eric-van-steenbergen/b/8a4/51b
parse_git_branch() {
git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(git::\1)/'
}

export PS1="\[\033[00m\]\u@\H:\[\033[01;34m\][\d \t][\w]\[\033[31m\]\$(parse_git_branch)\[\033[00m\]$\[\033[00m\] "
