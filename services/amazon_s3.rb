require 'aws-sdk'
require "amazon_s3/version"


module AmazonS3
  class Handler
    attr_accessor :access_key_id, :secret_access_key, :bucket_path, :bucket_name

    def initialize(access_key_id, secret_access_key, bucket_name, bucket_path = nil)
      raise "S3 credentials must be present" if access_key_id.blank? || secret_access_key.blank?
      raise "Busket name must be present" if bucket_name.blank? 

      self.access_key_id     = access_key_id
      self.secret_access_key = secret_access_key
      self.bucket_path       = bucket_path
      self.bucket_name       = bucket_name
    end

    def client
      c = AWS::S3.new({
        :access_key_id => self.access_key_id,
        :secret_access_key => self.secret_access_key
       })
    end

    def bucket
      client.buckets[self.bucket_name]
    end

    def upload_file(file_path)
      ext = Pathname.new(file_path).extname
      file_name = [SecureRandom.hex, ext].join
      object_path = [self.bucket_name, self.bucket_path, file_name].compact.join('/')
      s3_file = bucket.objects[object_path]
      s3_file.write Pathname.new(file_path)
      file_name
    end

    def download_file(file_name)
      object_path = [self.bucket_path, file_name].compact.join('/')
      s3_file = bucket.objects[object_path]
      ext = Pathname.new(file_name).extname
      file = Tempfile.new [file_name.sub(ext, ''), ext], Dir.tmpdir, :encoding => 'ascii-8bit'
      file.write s3_file.read
      file.rewind
      file
    end

    def get_image(file_name)
      object_path = [self.bucket_path, file_name].compact.join('/')
      s3_image = bucket.objects[object_path]
      ext = Pathname.new(file_name).extname
      file = Tempfile.new [file_name.sub(ext, ''), ext], Dir.tmpdir, :encoding => 'ascii-8bit'
      file.write s3_image.read
      file.rewind
      file
    end

    def get_file(file_name)
      s3_object = client.buckets[self.bucket_path].objects[file_name]
      ext = Pathname.new(file_name).extname
      file = Tempfile.new [file_name.sub(ext, ''), ext], Dir.tmpdir, :encoding => 'ascii-8bit'
      file.write s3_object.read
      file.rewind
      file
    end

    def dir_with_env
      self.bucket_path
    end
  end  
end
