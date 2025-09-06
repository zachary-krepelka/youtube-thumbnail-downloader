bind -N 'activate YouTube thumbnail mode' y switch-client -T youtube-thumbnails
bind -N 'get YouTube thumbnails' -T youtube-thumbnails g display-popup -d "#{pane_current_path}" -E youtube-thumbnail-manager.sh -q get
bind -N 'search YouTube thumbnails' -T youtube-thumbnails s display-popup -d "#{pane_current_path}" -EB -w100% -h100% youtube-thumbnail-manager.sh -q search
