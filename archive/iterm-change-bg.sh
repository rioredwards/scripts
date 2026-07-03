#bin/zsh!

change() {
    current_tty=$(tty)
    thumbnails='/Users/rioedwards/Pictures/iterm_bg_photos'
    images=(`ls $thumbnails`)
    num_images=${#images[*]}
    myfilename="${thumbnails}/`echo ${images[$((RANDOM%$num_images + 1))]}`"
    echo $myfilename > $current_tty
    base64filename=`echo ""${myfilename}"" | base64`;
    echo "\033]1337;SetBackgroundImageFile=${base64filename}\a" > $current_tty;
}

change
