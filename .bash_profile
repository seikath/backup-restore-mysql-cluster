# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
	. ~/.bashrc
fi

# User specific environment and startup programs

PATH=$PATH:$HOME/bin

export PATH
export PS1="\u@\H:[\d \t]:[\w]\$ " 
export KBUILD_NOPEDANTIC=1 
export LDFLAGS=-ldl 
export HISTSIZE=55000 
export HISTTIMEFORMAT="%F %T " 
export MYSQL_PS1="mysql\_\u@$HOSTNAME:[\D][\d]>\_"

