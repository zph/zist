require 'environs'
require 'logger'
require 's3'
require 'open-uri'
require 'mime/types'

class Zist
  attr_accessor :filename, :filepath, :bucket, \
                :bucket_name, :local_modified, :log, \
                :file_basename

  def initialize(filename, dir)
    @log            = setup_logger(STDOUT)
    @s3             = setup_s3_connection
    @filename       = filename
    @file_basename  = Pathname.new(filename).basename.to_s
    @filepath       = expand_filepath(dir, filename, @file_basename)
    @bucket_name    = Env.AMAZON_BLOG_BUCKET
    @bucket         = @s3.buckets.find bucket_name
    @local_modified = Time.at(File.stat(filepath).mtime).to_datetime
  end

  def upload
    if s3_copy_is_newer?
      log.warn('zist:upload'){ "Remote file is newer than local."}
      exit(42)
    end
    remote_filepath = File.join(Env.amazon_bucket_url, file_basename)
    log.info('zist:upload'){ "Pushing #{filepath} -> #{bucket_name}/#{file_basename}" }
    save_file!
    log.info('zist:upload'){ "#{remote_filepath.gsub(/http:/, 'https:')}" }
  end

  def expand_filepath(dir, filename, basename)
    begin
      path = File.join(dir, basename)
      case
      when File.exist?(filename) # absolute path not contingent on CWD of cmd
        File.expand_path(filename)
      when File.exists?(path)
        File.expand_path(path)
      else
        raise(ArgumentError)
      end
    rescue
      log.info('zist:expand_filepath'){ "File path can't be determined." }
      exit(2)
    end
  end

  private

  def save_file!
    return false if $DEBUG
    object = bucket.objects.build(file_basename)
    object.content = open(filepath)
    object.content_type = whose_mime_is_it_anyway
    object.save
  end

  def whose_mime_is_it_anyway
    possible_mime = MIME::Types.of(file_basename).first
    textfile = `file #{filepath}`.split(":", 2).last.chomp[/\btext\b/]
    case
    when possible_mime
      possible_mime
    when textfile
      MIME::Types['text/plain'].first
    else
      MIME::Types['application/octet-stream'].first
    end
  end

  def setup_logger(io = STDOUT)
    log = Logger.new(io) {|l| l.level = Logger::INFO }
  end

  def s3_copy_is_newer?
    begin
      existing = bucket.objects.find(filename)
    rescue S3::Error::ResponseError
      existing = false
    end
    (existing && local_modified < remote_file_timestamp(existing))
  end

  def remote_file_timestamp(existential_state)
    return DateTime.new(1066, 01, 01) unless existential_state
    existential_state.last_modified.to_datetime
  end

  def setup_s3_connection
    begin
      aws = S3::Service
      aws.new(access_key_id:     Env.amazon_key_id,
                                secret_access_key: Env.amazon_secret_key)
    rescue
      log.fatal('zist:setup_s3'){ "AWS Credentials missing or Invalid" }
      exit(1)
    end
  end
end
