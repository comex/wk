#!/usr/bin/env zsh
typeset -A kana
kana=(
    a   'あ'
    i   'い'
    u   'う'
    e   'え'
    o   'お'
    ka  'か'
    ki  'き'
    ku  'く'
    ke  'け'
    ko  'こ'
    ga  'が'
    gi  'ぎ'
    gu  'ぐ'
    ge  'げ'
    go  'ご'
    sa  'さ'
    si  'し'
    su  'す'
    se  'せ'
    so  'そ'
    za  'ざ'
    ji  'じ'
    zu  'ず'
    ze  'ぜ'
    zo  'ぞ'
    ta  'た'
    ti  'ち'
    tu  'つ'
    tsu  'つ'
    te  'て'
    to  'と'
    da  'だ'
    di  'ぢ'
    du  'づ'
    de  'で'
    do  'ど'
    na  'な'
    ni  'に'
    nu  'ぬ'
    ne  'ね'
    no  'の'
    ha  'は'
    hi  'ひ'
    fu  'ふ'
    he  'へ'
    ho  'ほ'
    ba  'ば'
    bi  'び'
    bu  'ぶ'
    be  'べ'
    bo  'ぼ'
    pa  'ぱ'
    pi  'ぴ'
    pu  'ぷ'
    pe  'ぺ'
    po  'ぽ'
    ma  'ま'
    mi  'み'
    mu  'む'
    me  'め'
    mo  'も'
    ya  'や'
    yu  'ゆ'
    yo  'よ'
    ra  'ら'
    ri  'り'
    ru  'る'
    re  'れ'
    ro  'ろ'
    wa  'わ'
    wo  'を'
    nn  'ん'
    shi 'し'
    chi 'ち'
    xya 'ゃ'
    xyu 'ゅ'
    xyo 'ょ'
    xtu 'っ'
    xtsu 'っ'
    # ***
    fe 'ふぇ'
    fa 'ふぁ'
    fi 'ふぃ'
    xa 'ぁ'
    xe 'ぇ'
    xi 'ぃ'
    xo 'ぉ'
    xu 'ぅ'
)

#for k in "${(@k)kana}"; do
#    echo ">$k ${kana[$k]}"
#done

autoload -U regexp-replace

rx="${(k)kana// /|}"

function subst() {
    text="$1"
    if [ "${text[1]}" != "!" ]; then
        #setopt re_match_pcre
        regexp-replace text '[mnrbphgk]y[aiueo]' '${MATCH[1]}ixy${MATCH[3]}'
        regexp-replace text '(sh|ch|j)[aueo]' '${MATCH[1,$#MATCH-1]}ixy${MATCH[$#MATCH]}'
        regexp-replace text 'kk|ss|cc|tt|ff|bb|pp' 'xtsu${MATCH[2]}'
        regexp-replace text "$rx" '${kana[$MATCH]}'
        #regexp-replace text "ku" "ik"
    fi

    print "$text"
}

#LANG=C subst '>> みゃku <<'
#echo "${kana[ku]}"
#exit

function self-insert() {
    zle .self-insert
    #echo "!self"
    #old="$LBUFFER"
    LBUFFER="$(subst "$LBUFFER")"
    #zle -M ">>> $old => $LBUFFER"
}
bad=0
function diaf() {
    bad=1
    exit
}
export LANG=en-US.utf-8
zle -N self-insert
zle -N diaf
bindkey '^D' diaf

line=
vared -p "$1" line
test "$bad" = "1" && exit 1
if [ "${line[1]}" != "!" ]; then
    line="${line//n/ん}"
fi
echo "$line"
