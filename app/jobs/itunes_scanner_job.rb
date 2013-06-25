require 'assets/parsers/itunes.rb'
require 'cjutils/path'

require 'base_job'

class ITunesLibraryScannerJob < BaseJob
  extend CJUtils::Path
  def initialize(source)
    @source_id = source.id
  end

  def priority
    Priority::HIGH
  end

  # start delayed_job hooks
  
  def perform
    halt = false
    Signal.trap('TERM') { halt = true }

    @src = Source.where(id: @source_id).first
    raise JobError.new("Source is no longer in database.") if @src.nil?

    uris = get_uris
    # remove tracks from database that are no longer in iTunes library
    @src.tracks.all.each do |track|
      next if uris.include?(URI::File.new_with_path(track.location))
      logger.info("Deleting #{track.uri} from database")
      track.destroy
      exit if halt
    end

    # add/update tracks
    uris.each do |uri|
      handle_uri(uri)
      exit if halt
    end

    update_source
  end

  # end delayed_job hooks
 
  def get_uris
    uris = []
    ITunesLibrary.parse(@src.location) do |track_info|
      track_info_normalized = normalize_track_info(track_info)
      
      if track_info_normalized.has_key?(:location)
        uris << URI(track_info_normalized[:location])
      end
    end

    uris
  end 

  def normalize_track_info(track_info)
    track_info_normalized = {}
    track_info.each do |key, value|
      track_info_normalized[self.class.normalize(key)] = value
    end

    track_info_normalized
  end

  def handle_uri(uri)
    fpath = self.class.uri_to_path(uri)
    if File.exists?(fpath)
      t = Track.track_for_file_path(fpath)
      unless t.sources.include?(@src)
        t.sources << @src
        t.save
      end
      
      now = Time.now
      if now - t.created_at < 5
        logger.info("Added #{fpath}")
      elsif now - t.updated_at < 5
        logger.info("Updated #{fpath}")
      end

    else
      logger.info("#{fpath} doesn't exist. Skipping.")
    end
  end

  def self.normalize(str)
    norm = str.downcase
    norm.gsub!(' ', '_')
    norm.to_sym
  end
end
