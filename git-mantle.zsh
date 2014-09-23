#!/usr/bin/env zsh
# vim: ts=2 sts=2 sw=2 et fdm=marker cms=\ #\ %s

set -o no_unset
set -o err_return

function complain
{
  print ${@[2,-1]} >&2
  exit $1
}

function query-git # {{{
{
  git show --no-patch --format=$1 "${@[2,-1]}"
} # }}}

declare do_stat=--stat=72 output=

while [[ $# -gt 0 && $1 == -* ]]; do
  case $1 in
  --output=*) output=${1#--output=} ;;
  --output)   shift; output=$1 ;;
  --stat* | --numstat)
              do_stat=$1 ;;
  esac
  shift
done

if [[ -n $output ]]; then
  exec > $output
fi

declare base head upstream public

mantle_upstream="$(git config mantle.upstream || :)"
mantle_upstream=${mantle_upstream:-upstream}
upstream=${mantle_upstream%%/*}
if [[ $mantle_upstream == ?*/?* ]]; then
  base=${mantle_upstream##*/}
else
  base=HEAD
fi

mantle_public="$(git config mantle.public || :)"
mantle_public=${mantle_public:-origin}
public=${mantle_public%%/*}
if [[ $mantle_public == ?*/?* ]]; then
  head=${mantle_public##*/}
else
  head=HEAD
fi

if (( $# > 1 )); then
  # slashless `base` is a *remote* name
  upstream=$1
  if [[ $upstream == ?*/?* ]]; then
    base=${upstream##*/}
    upstream=${upstream%%/*}
  fi
  shift
fi
if (( $# > 0 )); then
  # slashless `head` is a *branch* name
  head=$1
  if [[ $head == ?*/?* ]]; then
    public=${head%%/*}
    head=${head##*/}
  fi
fi

if [[ $base == HEAD ]]; then
  base=${${:-$(git symbolic-ref --short refs/remotes/$upstream/HEAD)}##*/} || exit 1
fi
if [[ $head == HEAD ]]; then
  head=$(git symbolic-ref --short $head)
fi

declare bspec=$upstream/$base
declare hspec=$public/$head
bspec=${bspec#./}
hspec=${hspec#./}

declare bhash hhash

bhash="$(query-git '%H' $bspec -- || exit 1)"
hhash="$(query-git '%H' $hspec -- || exit 1)"

declare mbase="$(git merge-base $bhash $hhash)" \
|| complain $? "fatal: no commits in common between $base and $head"

declare purl="$(git config --get remote.$public.url)"
[[ -z $purl ]] && purl='?'

declare -A chashes cmessages

# git-rev-list --format (or --pretty) prepends each commit
# with "commit %H\n".  it's easier to parse if we throw away
# this %H instance and request another one in the format string.
git rev-list --format='%T %H %s' $hhash --not $bhash \
| while read x y z; do
    [[ $x == commit ]] && continue
    chashes+=($x $y)
    cmessages+=($x $z)
  done

(( $#chashes )) || complain 1 "fatal: '$bspec..$hspec' is an empty range"

# repo = git@github.com:roman-neuhauser/anarchinst.git
# head = 6a91ccd3 readme-updates
# base = c7303d75 master
#
print -f 'repo = %s\n' $purl
print -f 'head = %s %s\n' $hhash $hspec
print -f 'base = %s %s\n' $bhash $bspec

if [[ -n $do_stat ]]; then
  print
  git diff-tree --summary $do_stat $hhash --not $mbase
  print
fi

# git rev-list --objects has the same output as without --objects,
# followed by, for each commit:
#   <tree-id> SP LF
#   <blob-id> SP <path> LF
#   ...
# we skip the initial run of lines that just list the <commit-id>s
declare -i i=0 nhashes=$#chashes
declare -i seqwidth=$#nhashes
declare -i totseqwidth=$((1 + 2*seqwidth))
git rev-list --reverse --objects $hhash --not $bhash \
| tail -n +$((1 + $nhashes)) \
| while read x y; do
    if [[ -z $y ]]; then # this is a <tree-id> line
      local chash=$chashes[$x]
      local cmesg=$cmessages[$x]
      print -f "%*d/%*d %s %s %s\n" -- \
        $seqwidth $((++i)) $seqwidth $nhashes \
        ${x:0:8} ${chash:0:8} $cmesg
      continue
    fi
    print -f "%*s %s %s\n" $totseqwidth '' ${x:0:8} $y
  done

