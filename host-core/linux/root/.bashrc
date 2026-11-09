# ~/.bashrc: executed by bash(1) for non-login shells.

PS1='\[\e[1;32m\][\u@\h \[\e[94;1m\]\w\[\e[1;32m\]]\$\[\e[m\] '

export LS_OPTIONS='--color=auto'
eval "$(dircolors)"
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -l'
alias l='ls $LS_OPTIONS -lA'

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
