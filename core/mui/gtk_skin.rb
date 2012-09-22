# -*- coding: utf-8 -*-

require 'gtk2'

module MUI
  class Skin

    def self.get(filename)
      fn = File.join(*[path, filename].flatten)
      return MUI::Skin.get('notfound.png') if 'notfound.png' != filename and not FileTest.exist?(fn)
      fn
    end

    def self.path
      %w(skin data)
    end

  end
end
