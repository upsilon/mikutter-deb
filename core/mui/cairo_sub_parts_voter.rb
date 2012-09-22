# -*- coding: utf-8 -*-

miquire :mui, 'sub_parts_helper'

require 'gtk2'
require 'cairo'

class Gdk::SubPartsVoter < Gdk::SubParts

  attr_reader :votes, :icon_width, :icon_height, :margin

  def initialize(*args)
    super
    @icon_width, @icon_height, @margin, @votes, @user_icon = 24, 24, 2, get_default_votes.to_a, Hash.new
    @icon_ofst = 0
    if not(helper.visible? or @votes.empty?)
      sid = helper.ssc(:expose_event){
        helper.on_modify
        helper.signal_handler_disconnect(sid)
        false } end
    helper.ssc(:click){ |this, e, x, y|
      ofsty = helper.mainpart_height
      helper.subparts.each{ |part|
        break if part == self
        ofsty += part.height }
      if ofsty <= y and (ofsty + height) >= y
        case e.button
        when 1
          if(x >= @icon_ofst)
            user = @votes[(x - @icon_ofst) / icon_width]
            if user
              commands = Plugin.filtering(:command, Hash.new).first
              command = commands[:show_profile]
              if command
                command[:exec][user] end end end end end
      false }
    last_motion_user = nil
    usertip = Gtk::Tooltips.new
    helper.ssc(:motion_notify_event){ |this, x, y|
      if 0 != height
        tipset = ''
        ofsty = helper.mainpart_height
        helper.subparts.each{ |part|
          break if part == self
          ofsty += part.height }
        if ofsty <= y and (ofsty + height) >= y
          if(x >= @icon_ofst)
            user = @votes[(x - @icon_ofst) / icon_width]
            last_motion_user = user
            if user
              tipset = user.idname end end end
        usertip.set_tip(helper.tree, tipset, '')
        if tipset == ''
          last_motion_user = nil
          usertip.disable
        else
          usertip.enable end end
      false }
    helper.ssc(:leave_notify_event){
      usertip.set_tip(helper.tree, '', '')
      usertip.disable
      false
    }
  end

  def render(context)
    if(not @votes.empty?)
      if helper.visible?
        context.save{
          context.translate(@margin, 0)
          context.set_source_rgb(*(UserConfig[:mumble_basic_color] || [0,0,0]).map{ |c| c.to_f / 65536 })
          plc = pl_count(context)
          context.save{
            context.translate(0, (icon_width/2) - (plc.size[1] / Pango::SCALE / 2))
            context.show_pango_layout(plc) }
          xpos = @icon_ofst = plc.size[0] / Pango::SCALE
          context.translate(@icon_ofst, 0)
          votes.each{ |user|
            render_icon(context, user)
            xpos += icon_width
            break if width <= xpos } } end end
    @last_height = height end

  def height
    if @votes.empty?
      0
    else
      icon_height end end

  def add(new)
    if UserConfig[:"#{name}_by_anyone_show_timeline"]
      if not @votes.include?(new)
        before_height = height
        @votes << new
        if(before_height == height)
          helper.on_modify
        else
          helper.reset_height end
        self end end end
  alias << add

  def delete(user)
    if UserConfig[:"#{name}_by_anyone_show_timeline"]
      if not @votes.include?(user)
        before_height = height
        @votes.delete(user)
        if(before_height == height)
          helper.on_modify
        else
          helper.reset_height end
        self end end end

  def name
    raise end

  def label
    raise end

  private

  def render_icon(context, user)
    context.set_source_pixbuf(user_icon(user))
    context.paint
    context.translate(icon_width, 0)
  end

  def user_icon(user)
    @user_icon[user[:id]] ||= Gdk::WebImageLoader.pixbuf(user[:profile_image_url], icon_width, icon_height){ |pixbuf|
      @user_icon[user[:id]] = pixbuf
      helper.on_modify } end

  def pl_count(context = dummy_context)
    layout = context.create_pango_layout
    layout.wrap = Pango::WRAP_CHAR
    layout.font_description = Pango::FontDescription.new(UserConfig[:mumble_basic_font])
    layout.text = "#{votes.size} #{label}"
    layout
  end

end
