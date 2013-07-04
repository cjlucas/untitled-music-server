require 'base_job'

class PurgeOrphanedImagesJob < BaseJob
  def perform
    Image.all.each do |image|
      image.destroy if image.tracks.empty?
    end
  end

  def priority
    Priority::LOW
  end
end
