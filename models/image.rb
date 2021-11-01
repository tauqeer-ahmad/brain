require 'RMagick'
class Image < ActiveRecord::Base

  include Magick

  cattr_accessor :valid_content_types
  @@valid_content_types = [
    'image/cgm', 'image/fits', 'image/g3fax', 'image/gif', 'image/ief',
    'image/jp2', 'image/jpeg', 'image/jpm', 'image/jpx', 'image/naplps',
    'image/png', 'image/prs.btif', 'image/prs.pti', 'image/t38', 'image/tiff',
    'image/tiff-fx', 'image/vnd.adobe.photoshop', 'image/vnd.cns.inf2',
    'image/vnd.djvu', 'image/vnd.dwg', 'image/vnd.dxf', 'image/vnd.fastbidsheet',
    'image/vnd.fpx', 'image/vnd.fst', 'image/vnd.fujixerox.edmics-mmr',
    'image/vnd.fujixerox.edmics-rlc', 'image/vnd.globalgraphics.pgb',
    'image/vnd.microsoft.icon', 'image/vnd.mix', 'image/vnd.ms-modi',
    'image/vnd.net-fpx', 'image/vnd.sealed.png', 'image/vnd.sealedmedia.softseal.gif',
    'image/vnd.sealedmedia.softseal.jpg', 'image/vnd.svf', 'image/vnd.wap.wbmp',
    'image/vnd.xiff', 'image/pjpeg',
  ]

  after_save :set_product_delta
  after_commit :watermark_images

  has_many :product_images
  has_many :products, :through => :product_images

  validates_attachment_presence :photo

  has_attached_file :photo,
                    :styles => {
                      :small    => {:geometry =>"52x36#",
                                    :format => :jpg,
                                    :convert_options => "-background white -compose Copy -gravity center -extent 78x54",
                                    },
                      :normal   => {:geometry =>"640x480",
                                    :format => :jpg,
                                    :convert_options => "-background white -compose Copy -gravity center -extent 640x480",
                                   },
                      :display  => {:geometry =>"260x180>",
                                   :format => :jpg,
                                   :convert_options => "-background white -compose Copy -gravity center -extent 260x180",
                                   },
                      :carousel => {:geometry =>"520x360>",
                                    :format => :jpg,
                                    :convert_options => "-background white -compose Copy -gravity center -extent 520x360",
                                   },
                      :big      => {:geometry => Proc.new { |a| a.original_geometry },
                                    :format => :jpg,
                                   },
                    },
                    :default_style => :normal,
                    :default_url => "/assets/images/default/:style/default.jpg",
                    :url  => "/assets/images/:id/:style/:basename.:extension",
                    :path => ":rails_root/public/assets/images/:id/:style/:basename.:extension"

  validates_attachment_content_type :photo,
                                    :message => 'file must be of valid image',
                                    :content_type => @@valid_content_types,
                                    :message => 'is invalid'

  scope :ordered, :order => 'id DESC'

  def set_product_delta
    self.products.each{|pr| pr.update_attributes :delta => true }
  end

  def watermark_images
    styles = self.photo.styles.keys.reject{|p| p == :display || p == :small}
    styles.each do |style|
      picture = Magick::Image.read(self.photo.path(style)).first
      watermark(picture)
    end
  end

  def watermark(picture)
    watermark_image = Magick::Image.read("#{Rails.root}/app/assets/images/watermark.png").first
    wms = watermark_image.scale(picture.columns, picture.rows)
    watermarked_picture = picture.composite(wms, Magick::CenterGravity, Magick::OverCompositeOp)
    watermarked_picture.write(picture.filename)
  end

  def original_geometry
    geo = Paperclip::Geometry.from_file(photo.queued_for_write[:original])
    "#{geo.width.to_i}x#{geo.height.to_i}#"
  end

end
