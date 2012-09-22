# -*- coding: utf-8 -*-
# 通知管理プラグイン

miquire :mui, 'tree_view_pretty_scroll'

require "set"

module Plugin::Activity
  # アクティビティを更新する。
  # ==== Args
  # [kind] Symbol イベントの種類
  # [title] タイトル
  # [args] その他オプション。主に以下の値
  #   icon :: String|Gdk::Pixbuf アイコン
  #   date :: Time イベントの発生した時刻
  #   service :: Service 関係するServiceオブジェクト
  #   related :: 自分に関係するかどうかのフラグ
  def activity(kind, title, args = {})
    Plugin.call(:modify_activity,
                { plugin: self,
                  kind: kind,
                  title: title,
                  date: Time.new,
                  description: title }.merge(args))
  end
end

class Plugin
  include Plugin::Activity

  def self.activity(kind, title, args = {})
    Plugin.call(:modify_activity,
                { plugin: nil,
                  kind: kind,
                  title: title,
                  date: Time.new,
                  description: title }.merge(args))
  end
end

Plugin.create(:activity) do
  class ActivityView < Gtk::CRUD
    include Gtk::TreeViewPrettyScroll

    ICON = 0
    KIND = 1
    TITLE = 2
    DATE = 3
    PLUGIN = 4
    ID = 5
    SERVICE = 6
    EVENT = 7

    def initialize
      super()
      @creatable = @updatable = @deletable = false
    end

    def column_schemer
      [{:kind => :pixbuf, :type => Gdk::Pixbuf, :label => 'icon'}, # ICON
       {:kind => :text, :type => String, :label => '種類'},        # KIND
       {:kind => :text, :type => String, :label => '説明'},        # TITLE
       {:kind => :text, :type => String, :label => '時刻'},        # DATE
       {:type => Plugin},                                          # PLUGIN
       {:type => Integer},                                         # ID
       {:type => Service},                                         # SERVICE
       {:type => Hash} ].freeze                                    # EVENT
    end
  end

  BOOT_TIME = Time.new.freeze

  # そのイベントをミュートするかどうかを返す(trueなら表示しない)
  def mute?(params)
    mute_kind = UserConfig[:activity_mute_kind]
    if mute_kind.is_a? Array
      return true if mute_kind.include? params[:kind].to_s end
    mute_kind_related = UserConfig[:activity_mute_kind_related]
    if mute_kind_related
      return true if mute_kind_related.include?(params[:kind].to_s) and !params[:related] end
    false end

  # このIDの組み合わせが出現したことがないなら真
  # ==== Args
  # [event] イベント名
  # [ids] ID
  # ==== Return
  # 初めて表示するキーなら真
 def show_once(event, *ids)
   @show_once ||= Hash.new{ |h, k| h[k] = [] }
   result = []
   ids.each_with_index{ |id, index|
     storage = @show_once[event][index] ||= Set.new
     if storage.include? id
       result << true
     else
       storage << id
       result << false end }
   notice "#{event}: #{ids.inspect} -> #{result.inspect} #{not result.all?(&ret_nth)}"
   not result.all?(&ret_nth) end

  activity_view = ActivityView.new
  activity_vscrollbar = Gtk::VScrollbar.new(activity_view.vadjustment)
  activity_hscrollbar = Gtk::HScrollbar.new(activity_view.hadjustment)
  activity_shell = Gtk::Table.new(2, 2)
  activity_description = Gtk::IntelligentTextview.new
  activity_status = Gtk::Label.new
  activity_container = Gtk::VBox.new

  activity_container.
    pack_start(activity_shell.
               attach(activity_view, 0, 1, 0, 1, Gtk::FILL|Gtk::SHRINK|Gtk::EXPAND, Gtk::FILL|Gtk::SHRINK|Gtk::EXPAND).
               attach(activity_vscrollbar, 1, 2, 0, 1, Gtk::FILL, Gtk::SHRINK|Gtk::FILL).
               attach(activity_hscrollbar, 0, 1, 1, 2, Gtk::SHRINK|Gtk::FILL, Gtk::FILL)).
    closeup(activity_description).
    closeup(activity_status.right)

  Delayer.new do
    Plugin.call(:mui_tab_regist, activity_container, 'アクティビティ', MUI::Skin.get("underconstruction.png"))
  end

  activity_view.ssc("cursor-changed") { |this|
    iter = this.selection.selected
    if iter
      activity_description.rewind(iter[ActivityView::EVENT][:description])
      activity_status.set_text(iter[ActivityView::DATE])
    end
    false
  }

  # アクティビティ更新を受け取った時の処理
  # plugin, kind, title, icon, date, service
  on_modify_activity do |params|
    if not mute?(params)
      iter = activity_view.model.prepend
      if params[:icon].is_a? String
        iter[ActivityView::ICON] = Gdk::WebImageLoader.pixbuf(params[:icon], 24, 24){ |loaded_icon|
          iter[ActivityView::ICON] = loaded_icon }
      else
        iter[ActivityView::ICON] = params[:icon] end
      iter[ActivityView::KIND] = params[:kind].to_s
      iter[ActivityView::TITLE] = params[:title].tr("\n", "")
      iter[ActivityView::DATE] = params[:date].strftime('%Y/%m/%d %H:%M:%S')
      iter[ActivityView::PLUGIN] = params[:plugin]
      iter[ActivityView::ID] = 0
      iter[ActivityView::SERVICE] = params[:service]
      iter[ActivityView::EVENT] = params
      if (UserConfig[:activity_show_timeline] || []).include?(params[:kind].to_s)
        Plugin.call(:update, nil, [Message.new(message: params[:description], system: true, source: params[:plugin].to_s, created: params[:date])])
      end
    end
  end

  on_favorite do |service, user, message|
    activity(:favorite, "#{message.user[:idname]}: #{message.to_s}",
             description:("@#{user[:idname]} がふぁぼふぁぼしました\n"+
                          "@#{message.user[:idname]}: #{message.to_s}\n"+
                          "https://twitter.com/#!/#{message.user[:idname]}/statuses/#{message[:id]}"),
             icon: user[:profile_image_url],
             related: message.user.is_me? || user.is_me?,
             service: service)
  end

  on_unfavorite do |service, user, message|
    activity(:unfavorite, "#{message.user[:idname]}: #{message.to_s}",
             description:("@#{user[:idname]} があんふぁぼしました\n"+
                          "@#{message.user[:idname]}: #{message.to_s}\n"+
                          "https://twitter.com/#!/#{message.user[:idname]}/statuses/#{message[:id]}"),
             icon: user[:profile_image_url],
             related: message.user.is_me? || user.is_me?,
             service: service)
  end

  on_retweet do |retweets|
    retweets.each { |retweet|
      retweet.retweet_source_d.next{ |source|
        activity(:retweet, retweet.to_s,
                 description:("@#{retweet.user[:idname]} がリツイートしました\n"+
                              "@#{source.user[:idname]}: #{source.to_s}\n"+
                              "https://twitter.com/#!/#{source.user[:idname]}/statuses/#{source[:id]}"),
                 icon: retweet.user[:profile_image_url],
                 date: retweet[:created],
                 related: (retweet.user.is_me? || source && source.user.is_me?),
                 service: Service.primary) }.terminate('リツイートソースが取得できませんでした') }
  end

  on_list_member_added do |service, user, list, source_user|
    if show_once(:list_member_added, user[:id], list[:id])
      activity(:list_member_added, "@#{user[:idname]}が#{list[:full_name]}に追加されました",
               description:("@#{user[:idname]} が #{list[:full_name]} に追加されました\n"+
                            "#{list[:description]} (by @#{list.user[:idname]})\n"+
                            "https://twitter.com/#!/#{list.user[:idname]}/#{list[:slug]}"),
               icon: user[:profile_image_url],
               related: user.is_me? || source_user.is_me?,
               service: service) end
  end

  on_list_member_removed do |service, user, list, source_user|
    if show_once(:list_member_removed, user[:id], list[:id])
      activity(:list_member_removed, "@#{user[:idname]}が#{list[:full_name]}から削除されました",
               description:("@#{user[:idname]} が #{list[:full_name]} から削除されました\n"+
                            "#{list[:description]} (by @#{list.user[:idname]})\n"+
                            "https://twitter.com/#!/#{list.user[:idname]}/#{list[:slug]}"),
               icon: user[:profile_image_url],
               related: user.is_me? || source_user.is_me?,
               service: service) end
  end

  on_follow do |by, to|
    if show_once(:follow, by[:id], to[:id])
      activity(:follow, "@#{by[:idname]}が@#{to[:idname]}をﾌｮﾛｰしました",
               related: by.is_me? || to.is_me?,
               icon: (to.is_me? ? by : to)[:profile_image_url]) end
  end

  on_direct_messages do |service, dms|
    dms.each{ |dm|
      date = Time.parse(dm[:created_at])
      if date > BOOT_TIME
        first_line = dm[:sender].is_me? ? "ダイレクトメッセージを送信しました" : "ダイレクトメッセージを受信しました"
        activity(:dm, "D #{dm[:recipient][:idname]} #{dm[:text]}",
                 description: ("#{first_line}\n" +
                               "@#{dm[:sender][:idname]}: D #{dm[:recipient][:idname]} #{dm[:text]}"),
                 icon: dm[:sender][:profile_image_url],
                 service: service,
                 date: date) end }
  end

  onunload do
    Addon.remove_tab 'アクティビティ'
  end

  settings "アクティビティ" do
    settings "表示しないイベント" do
      multiselect("以下の自分に関係ないイベント", :activity_mute_kind_related) do
        option "retweet", "リツイート"
        option "favorite", "ふぁぼ"
        option "follow", "フォロー"
        option "list_member_added", "リストに追加"
        option "list_member_removed", "リストから削除"
        option "dm", "ダイレクトメッセージ"
        option "system", "システムメッセージ"
        option "error", "エラー"
      end

      multiselect("以下の全てのイベント", :activity_mute_kind) do
        option "retweet", "リツイート"
        option "favorite", "ふぁぼ"
        option "follow", "フォロー"
        option "list_member_added", "リストに追加"
        option "list_member_removed", "リストから削除"
        option "dm", "ダイレクトメッセージ"
        option "system", "システムメッセージ"
        option "error", "エラー"
      end
    end

    multiselect("タイムラインに表示", :activity_show_timeline) do
      option "retweet", "リツイート"
      option "favorite", "ふぁぼ"
      option "follow", "フォロー"
      option "list_member_added", "リストに追加"
      option "list_member_removed", "リストから削除"
      option "dm", "ダイレクトメッセージ"
      option "system", "システムメッセージ"
      option "error", "エラー"
    end

  end
end
