require_dependency RAILS_ROOT + "/vendor/plugins/substruct/app/models/product"

class Product < Item
  has_many :comments, :dependent => :destroy
  has_and_belongs_to_many :tags, :order => :name
  
  # different ranking...
  has_many :images,
    :through => :product_images, :order => "-product_images.rank DESC",
    :dependent => :destroy
  

  def sync_all_parent_tags
    tags = self.tags + self.tags.select{|t| t.parent}.map{|t| t.parent}
     tags.each{|t|
      if t.parent && t.parent.products.count > 0 && !t.parent.id.in?(self.tag_ids)
        self.tags << t.parent
      end
    }
  end

  # the arranger tag for this product...if there is one...or nil if not
  def composer_tag
   self.tags.select{|t| t.is_composer_tag? }[0]
  end
  
  def hymn_tag
   self.tags.select{|t| t.is_hymn_tag? }[0]
  end

  def original_tag
   self.tags.select{|t| t.is_original_tag? }[0]
  end 

  def composer_contact
     owner = composer_tag
     cc = (owner && owner.composer_contact.present? ) ? owner.composer_contact : nil
     cc = "mailto:" + cc if cc =~ /.@./
     cc
  end
  
  # my own version :P
  def tag_ids=(list)
    tags.clear
    for id in list
      if !id.to_s.empty?
        tags << Tag.find(id) if !id.to_s.empty?
      end
    end
  end

  # Inserts code from product name if not entered.
  # Makes code safe for URL usage.
  # called via a before_save :clean_code
  def clean_code
    if self.code.blank?
      if self.composer_tag
        self.code = self.name.clone + '--by-' + self.composer_tag.name
      else
        self.code = self.name.clone
      end
    end
#    self.code.upcase!
    self.code = self.code.gsub(/[^[:alnum:]]/,'-')#.gsub(/-{2,}/,'-')
    self.code = self.code.gsub(/^[-]/,'').gsub(/[-]$/,'')
    self.code.strip!
    return true
  end

  def topic_tags
    tags.select{|t| t.parent && t.parent.name == "Topics"}
  end

  # for manual use, currently...
  def self.all_songs_without_topics
    self.all.select{|p| p.topic_tags.length == 0}
  end

  def self.super_sum
    count = 0; all.each{|dl| count += dl.view_count}; count
  end

  # too strong!
  # after_save { Cache.delete_all }
  # done in the admin now

  def find_problems
      problems = []
      if self.topic_tags.length == 0
        problems << "Warning: no topics associated with song yet."
      end
      if !self.hymn_tag && !self.tags.detect{|t| t.name =~ /original/i}
        problems <<  "Warning: no hymn or 'original' tag for this song yet."
      end
      if self.downloads.size == 0 && !self.original_url.present?
        problems << "Warning: song has no original_url nor pdf uploads! Not expected I don't think..."
      end
      if self.original_url.present? && !self.original_url.start_with?("http")
        problems << "original url should start with http://"
      end
      if self.original_url =~ /\.(pdf|mp3|mid|midi)/
        problems << "original url looks like its a pdf but should be htmlish"
      end
      if !self.tags.detect{|t| t.is_voicing}
        problems << "Warning: no voicing [youth, SATB, etc.] seemingly found"
      end
      if self.composer_tag && self.composer_tag.composer_contact !~ /@/
        problems << "Possibly lacking an original_url?" unless self.original_url.present?
      end
      if (count = Product.count(:conditions => {:code => self.code})) != 1
        problems << "probably not a unique product code please update #{count}"
      end
      if self.hymn_tag && self.name != self.hymn_tag.name
         problems << "possibly mispelled [doesnt match hymn--might be expected/capitalization]--#{self.hymn_tag.name}"
      end
      unless self.composer_tag
         problems << "song has no composer tag?"
      end
      if self.composer_tag && !self.composer_tag.composer_contact.present?
         problems << "composer associated with this song has not contact info?"
      elsif self.composer_tag && (self.composer_tag.composer_contact !~ /@/ && !self.composer_tag.composer_contact.start_with?('http'))
         problems << "composer associated with this song might have bad url, should start with http?"
      end
      if !self.hymn_tag && (t = Tag.find_by_name(self.name) )
         unless t.id.in? self.tag_ids
           problems << "song probably should be tagged with hymn name, or topic"
         end
      end
      for tag in self.tags
        if tag.children.length > 0
          if (tag.child_ids - self.tag_ids).length == tag.child_ids.length
            problems << "probably needs a child tag beneath #{tag.name}"
          end
        end
      end
      problems
  end

  def linkable_tags user
    if user
      tags
    else
      tags.select{|t| !(t.is_hymn_tag? || t.is_composer_tag?)}.reject{|t| (t.child_ids - self.tag_ids) != t.child_ids}
     end
  end

end
