# -*- coding: utf-8 -*-

require File.expand_path File.join(File.dirname(__FILE__), 'userlist')
require File.expand_path File.join(File.dirname(__FILE__), 'sender')
require File.expand_path File.join(File.dirname(__FILE__), 'dmlistview')

module Plugin::DirectMessage
  Plugin.create(:directmessage) do

    # user_id => [Direct Message...]
    @dm_store = Hash.new{|h, k|
      Plugin.call(:direct_message_add_user, k)
      h[k] = [] }
    @dm_lock = Mutex.new
    @counter = gen_counter

    onboot do
      @userlist = UserList.new.show_all
      @userlist.double_clicked = lambda{ |user|
        Plugin.call(:show_profile, Service.primary_service, user) }
      Delayer.new{
        Plugin.call(:mui_tab_regist, @userlist, 'Direct Message', MUI::Skin.get("directmessage.png"))
      }
    end

    onperiod do
      service = Service.primary_service
      if 0 == (@counter.call % UserConfig[:retrieve_interval_direct_messages])
        Deferred.when(service.direct_messages, service.sent_direct_messages).next{ |dm, sent|
          result = dm + sent
          Plugin.call(:direct_messages, service, result) if result and not result.empty? }.terminate end end

    filter_direct_messages do |service, dms|
      if defined? dms.sort_by
        result = []
        @dm_lock.synchronize do
          dms.sort_by{ |s| Time.parse(s[:created_at]) rescue Time.now }.each { |dm|
            if add_dm(dm, dm[:sender]) and add_dm(dm, dm[:recipient])
              result << dm end } end
        [service, result]
      else
        [service, dms] end end

    on_direct_message_add_user do |user_id|
      user = User.findbyid(user_id)
      if user.is_a? User
        user[:last_dm_date] ||= 0
        @userlist.block_add(user)
      end
    end

    filter_profile_tab do |notebook, user|
      notebook.append_page(dm_list_widget(user), Gtk::WebIcon.new(MUI::Skin.get("directmessage.png"), 16, 16).show_all)
      [notebook, user]
    end

    def call_api(service, api)
      service.call_api(api, :count => UserConfig[:retrieve_count_direct_messages]) end

    def add_dm(dm, user)
      unless @dm_store[user[:id]].any?{ |stored| stored[:id] == dm[:id] }
        created_at = Time.parse(dm[:created_at]).to_i
        if user[:last_dm_date] and user[:last_dm_date] < created_at
          user[:last_dm_date] = created_at
          Delayer.new{ @userlist.modify_date(user) } end
        @dm_store[user[:id]] << dm end
    end

    def dm_list_widget(user)
      container = Gtk::VBox.new
      tl = DirectMessage.new

      scrollbar = Gtk::VScrollbar.new(tl.vadjustment)
      model = tl.model
      @dm_lock.synchronize do
        if @dm_store.has_key?(user[:id])
          @dm_store[user[:id]].each { |dm|
            iter = model.append
            iter[DirectMessage::C_CREATED] = Time.parse(dm[:created_at]).to_i
            iter[DirectMessage::C_ICON] = Gdk::WebImageLoader.pixbuf(dm[:sender][:profile_image_url], 16, 16) { |pixbuf|
              iter[DirectMessage::C_ICON] = pixbuf }
            iter[DirectMessage::C_TEXT] = dm[:text]
            iter[DirectMessage::C_RAW] = dm } end end

      event = on_direct_messages do |service, dms|
        if not tl.destroyed?
          dms.each{ |dm|
            if user[:id].to_i == dm[:sender][:id].to_i or user[:id].to_i == dm[:recipient][:id].to_i
              iter = model.append
              iter[DirectMessage::C_CREATED] = Time.parse(dm[:created_at]).to_i
              iter[DirectMessage::C_ICON] = Gdk::WebImageLoader.pixbuf(dm[:sender][:profile_image_url], 16, 16) { |pixbuf|
                iter[DirectMessage::C_ICON] = pixbuf }
              iter[DirectMessage::C_TEXT] = dm[:text]
              iter[DirectMessage::C_RAW] = dm end } end end

      tl.ssc(:scroll_event){ |this, e|
        case e.direction
        when Gdk::EventScroll::UP
          this.vadjustment.value -= this.vadjustment.step_increment
        when Gdk::EventScroll::DOWN
          this.vadjustment.value += this.vadjustment.step_increment end
        false }

      tl.ssc(:destroy){
        detach(:direct_message, event)
      }
      mumbles = Gtk::VBox.new(false, 0)
      postbox = Gtk::PostBox.new(Sender.new(Service.primary_service, user), :postboxstorage => mumbles, :delegate_other => true)
      mumbles.pack_start(postbox)
      container.closeup(mumbles).add(Gtk::HBox.new.add(tl).closeup(scrollbar))
      container
    end

  end
end

