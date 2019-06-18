class Course < ActiveRecord::Base
  include Tire::Model::Search

  scope :elastic_eager_loaded, includes([{library: [:attachments, :currency, :content, :partner_libraries, :skills, :scrapes]}, :content, :attachments, :course_skills, :topics, :topic, :ratings, :article_courses, :course_type, :currency, skills: [:topics, :content, :topic]])

  tire.settings ELASTIC_SEARCH_SETTINGS['course']

  after_save    :reindex
  after_destroy :remove_index

  mapping do
    indexes "active",                   :type => "boolean",  :index => :not_analyzed, :include_in_all => false
    indexes "search_active",            :type => "boolean",  :index => :not_analyzed, :include_in_all => false
    indexes "online",                   :type => "boolean",  :index => :not_analyzed, :include_in_all => false
    indexes "deleted",                  :type => "boolean",  :index => :not_analyzed, :include_in_all => false
    indexes "space_lock",               :type => "string",   :index => :not_analyzed, :include_in_all => false
    indexes "time_lock",                :type => "string",   :index => :not_analyzed, :include_in_all => false

    indexes "id",                       :type => "integer",  :index => :not_analyzed, :include_in_all => false
    indexes "partner_id",               :type => "integer",  :index => :not_analyzed, :include_in_all => false
    indexes "article_id",               :type => "integer",  :index => :not_analyzed, :include_in_all => false
    indexes "course_type_id",           :type => "integer",  :index => :not_analyzed, :include_in_all => false
    indexes "library_id",               :type => "integer",  :index => :not_analyzed, :include_in_all => false
    indexes "custom_score",             :type => "integer",  :index => :not_analyzed, :include_in_all => false
    indexes "rating_count",             :type => "integer",  :index => :not_analyzed, :include_in_all => false
    indexes "view_count",               :type => "integer",  :index => :not_analyzed, :include_in_all => false
    indexes "product_quality",          :type => "integer",  :index => :not_analyzed, :include_in_all => false
    indexes "topic_id",                 :type => "integer",  :index => :not_analyzed, :include_in_all => false
    indexes "price_in_cents",           :type => "integer",  :index => :not_analyzed, :include_in_all => false


    indexes "price",                    :type => "float",    :index => :not_analyzed, :include_in_all => false
    indexes "price_filter",             :type => "float",    :index => :not_analyzed, :include_in_all => false
    indexes "average_rating",           :type => "float",    :index => :not_analyzed, :include_in_all => false

    indexes "date",                     :type => "date",     :index => :not_analyzed, :include_in_all => false,  :format => "basic_date"
    indexes "created_at",               :type => "date",     :index => :not_analyzed, :include_in_all => false,  :format => "basic_date_time_no_millis"
    indexes "started_at",               :type => "date",     :index => :not_analyzed, :include_in_all => false,  :format => "basic_date_time_no_millis"
    indexes "updated_at",               :type => "date",     :index => :not_analyzed, :include_in_all => false,  :format => "basic_date_time_no_millis"

    indexes "library_db_name",          :type => "string",   :index => :not_analyzed, :include_in_all => false
    indexes "slug",                     :type => "string",   :index => :not_analyzed, :include_in_all => false
    indexes "title",                    :type => "string",   :index => :analyzed,     :include_in_all => true, :analyzer => 'english_skills_snowball',
      "fields" => {
        "raw" => {
          "type"  =>  "string",
          "index" =>  "not_analyzed"
        }
      }
    indexes "description",              :type => "string",   :index => :analyzed,     :include_in_all => true, :analyzer => 'english_skills_snowball'
    indexes "library_name",             :type => "string",   :index => :analyzed,     :include_in_all => true, :analyzer => 'english_skills_snowball'
    indexes "library_special_keywords", :type => "string",   :index => :analyzed,     :include_in_all => true, :analyzer => 'english_skills_snowball'
    indexes "topic_name",               :type => "string",   :index => :analyzed,     :include_in_all => true, :analyzer => 'english_skills_snowball'

    indexes "uuid",                     :type => "string",   :index => :not_analyzed, :include_in_all => false
    indexes "product_type_name",        :type => "string",   :index => :not_analyzed, :include_in_all => false
    indexes "sub_length",               :type => "string",   :index => :not_analyzed, :include_in_all => false
    indexes "timezone",                 :type => "string",   :index => :not_analyzed, :include_in_all => false
    indexes "status",                   :type => "string",   :index => :not_analyzed, :include_in_all => false

    indexes "keywords",                 :type => "nested" do
      indexes "keyword_id",             :type => "integer",   :index => :not_analyzed, :include_in_all => false
      indexes "score",                  :type => "integer",   :index => :not_analyzed, :include_in_all => false
    end
  end

  def remove_index
    self.tire.index.remove self
    refresh_index
  end

  def refresh_index
    Course::Search.invalidate_cache
    return unless Rails.env.test?
    self.tire.index.refresh
  end

  def reindex
    return if without_reindex?

    self.tire.index.store self
    refresh_index
  end

  def computed_course_type_relevance
    course_type_id = self.library.present? && self.course_type_id || nil
    {
      1 => 5,
      2 => 4,
      3 => 3,
      4 => 1,
      5 => 2,
    }[course_type_id] || 6
  end

  def computed_price_relevance
    p = self.rounded_price
    return 0 unless p
    return 1000-p
  end

  def course_tags(options = {})
    course_tags = {}

    course_tags[:duration] = self.duration && self.duration > 0 ? self.formatted_duration : self.duration_text
    course_tags[:difficulty] = course_tags[:level] = self.level
    course_tags[:author_text] = self.authors_text || (self.authors.is_a?(Array) ? self.authors.to_a.map { |author| author['name'] } : [])
    course_tags[:category] = self.category

    course_tags
  end

  def as_v2_json(options = {})
    h = {}

    h[:id]               = self.id
    h[:uuid]             = self.uuid
    h[:title]            = h[:name] = self.title.html_escape_recursive
    h[:slug]             = self.slug
    h[:to_param]         = self.to_param
    h[:description]      = self.description
    h[:price]            = self.final_price
    h[:price_display_float] = self.price
    h[:display_price]    = self.display_price
    h[:price]          ||= -1
    h[:original_price]   = h[:price_display_float_orig] = self.price_amount
    h[:sub_length]       = self.sub_length
    h[:video_code]       = self.video_code
    h[:certificate]      = self.certificate
    h[:library]          = self.library.present? && self.library.as_v2_json(options) || {}
    h[:tags]             = self.course_tags.html_escape_recursive
    h[:created_at]       = h[:created_date] = self.created_at.to_elastic_time
    h[:updated_at]       = h[:modified_date] = self.updated_at.to_elastic_time
    h[:deleted_at]       = self.deleted_at.try :to_elastic_time
    h[:manually_collected] = self.manually_collected?
    h[:price_filter] = self.normalized_price
    h[:price_filter] ||= -1
    h[:price_in_cents] = self.normalized_price && self.normalized_price.round(2) * 100 || -1
    h[:space_lock] = self.space_lock.to_e || "X"
    h[:time_lock] = self.time_lock.to_e || "X"
    h[:short_description] = h[:short_desc] = self.short_description
    h[:display_short_description] = self.display_short_description
    h[:average_rating] = h[:rating_ave] = self.average_rating
    h[:ProductRating] = h[:rating_count] = h[:rating_cnt] = self.ratings.length
    h[:view_cnt] = h[:view_count] = self.view_count
    h[:started_at] = self.started_at.to_datetime.try(:strftime, "%Y%m%d") if self.started_at.present?
    h[:tz] = h[:timezone] = self.timezone
    h[:location_addr] = h[:location_address] = self.location_address
    h[:location_city] = self.location_city
    h[:location_country] = self.location_country
    h[:location_state] = self.location_state
    h[:location_postal] = h[:location_zip_code] = self.location_zip_code
    h[:product_quality] = self.library.try(:quality_rating)
    h[:status] = self.status
    h[:price_display_text] = price_info[:display_text]
    h[:currency_id] = self.library.try(:currency_id)
    h[:currency_symbol] = self.currency_or_default.try(:symbol)
    h[:latitude] = self.latitude
    h[:publisher] = self.publisher.to_s
    h[:formats] = self.formats
    h[:longitude] = self.longitude
    h[:provider_name] = self.library.try(:name)
    product_image_url = if self.product_image_url.present? && self.product_image_url.is_a?(Array)
      self.product_image_url.map { |image| image.gsub(' ', '+') }
    elsif self.product_image_url.present?
      self.product_image_url.gsub(' ', '+')
    end
    h[:product_image_url] = product_image_url
    h[:author_name] = self.authors.is_a?(Array) ? self.authors.map { |author|author['name'] }.join(", ").to_e : nil
    h[:start_date_utm] = self.started_at
    h[:end_date_utm] = self.ended_at
    h[:start_date_local] = self.started_at.present? ? Time.parse([self.started_at, self.timezone].join(' ')) : nil
    h[:end_date_local] = self.ended_at.present? ? Time.parse([self.ended_at, self.timezone].join(' ')) : nil
    h[:product_type_name] = h[:course_type_name] = self.course_type.try(:name) || ''
    h[:duration_display] = self.duration && self.duration > 0 ? self.formatted_duration : self.duration_text
    h[:provider_description] = self.library.try(:description)
    h[:price_currency] = self.currency_or_default.try(:name)
    h[:provider_icon_url] = self.provider_icon_url
    h[:product_video_url] = self.product_video_url
    h[:formats] = self.formats
    h[:product_url] = self.affiliate_target_url
    h[:original_product_url] = self.target_url
    h[:difficulty] = self.level
    h[:display_difficulty_level] = self.display_difficulty_level
    h[:url] = "/courses/#{h[:slug]}"
    h[:published_date] = self.published_dt
    h[:instructors] = self.get_instructors
    h[:instructor_name] = self.primary_instructor_name
    h[:language] = self.language
    h[:pub_status] = "L" if self.status == "live"
    h[:partner_prod_id] = self.partner_prod_id
    h[:review_cnt] = self.ratings.select { |rating| rating.review.present? }.count
    h[:product_events] = self.events.collect(&:as_json)
    h[:SkillProduct] = self.skills.collect &:as_v2_json

    h.merge!(self.imageable_attributes)

    h
  end

  def as_v2_indexed_json(options = {})
    h = {}

    h[:provider_id]    = h[:library_id] = self.library_id.to_i
    h[:search_active]  = self.status == 'live' && self.library.try(:status) == 'live'
    h[:product_type_id] = h[:course_type_id] = self.course_type_id.to_i
    h[:partner_id]     = self.library.present? && self.library.partner_libraries.collect(&:partner_id).collect(&:to_i) || []
    h[:deleted]        = self.deleted?

    h[:custom_score]  = (self.library.try(:quality_rating).to_i * RankingFactor.get.library_quality_score.to_f + computed_price_relevance * RankingFactor.get.price.to_f + computed_course_type_relevance * RankingFactor.get.course_type.to_f)

    h[:library_special_keywords] = self.library.present? && self.library.skills.collect {|skill| skill.name.downcase} || []

    h[:keywords] = self.course_skills.collect do |course_skill|
      {keyword_id: course_skill.skill_id, score: course_skill.score}
    end

    h[:keywords] << {keyword_id: 0, score: 0} if h[:keywords].empty?
    h[:topic_name] = self.all_topics.first.try(:name)
    topic_ids = self.all_topics.collect(&:id).collect(&:to_i)
    h[:topic_id] = topic_ids.present? ? topic_ids : [0]
    h[:article_id] = self.article_courses.collect(&:article_id).collect(&:to_i)

    h
  end

  def as_indexed_json(options = {})
    h = {}
    h.merge! as_v2_json(options)
    h.merge! as_v2_indexed_json(options)
    h
  end

  def to_indexed_json(options = {})
    as_indexed_json(options).to_json
  end

  class Search
    include Searchable

    class << self

      def v2_class
        Api::V3::Courses
      end

      def rebuild_index_from_scratch
        new_index_name = "courses_#{Time.now.strftime('%d_%m_%Y_%H_%M')}"

        index = Tire.index new_index_name do
          delete
          create :settings => ELASTIC_SEARCH_SETTINGS['course'], :mappings => {:course => {:properties => Course.mapping}}
        end

        reindex(new_index_name)
        delete_index
        Tire::Alias.create name: 'courses', indices: [new_index_name]
      end

      def reindex(index_name = nil)
        counter = 0
        total_duration = 0

        total = Course.count

        index_obj = Course.tire.index
        index_obj = Tire.index(index_name) if index_name.present?

        Course.elastic_eager_loaded.find_in_batches(batch_size: 500) do |courses|
          log "=== Importing ==="
          log "Importing #{courses.length} courses (#{(counter*100.0/total).round(2)}%) ..."
          duration = Benchmark.ms { index_obj.import courses }
          total_duration += duration
          log "Finished in #{(duration/1000).round(2)}s"
          counter += courses.length
        end

        log "Import completed in #{(total_duration/1000).round(2)}s"

        invalidate_cache
      end

    end

    def get_keywords(skill = nil, keyword = nil)
      return simple_keywords(keyword) if skill.blank?
      return keywords_with_synonyms(skill) if keyword.to_s.strip.downcase == skill.name.to_s.strip.downcase
      return simple_keywords(keyword)
    end

    def keywords_with_synonyms(skill)
      keywords = []
      keywords << skill.name
      keywords
    end

    def simple_keywords(keyword)
      [keyword.to_e].compact
    end

    def string_elastic_query_fields
      ["title^#{RankingFactor.get.title_text_match.to_f}", "description^#{RankingFactor.get.description_text_match.to_f}", "library_special_keywords^#{RankingFactor.get.library_special_keywords.to_f}", "library_name^#{RankingFactor.get.library_special_keywords.to_f}"]
    end

    def elastic_started_at_facets_for(key)
      {
        "size" => 500,
        "range" => {
          "field" => key,
          "ranges" => [
            { "from" => Time.now.utc.to_elastic_time, "to" => 7.days.since.to_elastic_time },
            { "from" => Time.now.utc.to_elastic_time, "to" => 14.days.since.to_elastic_time },
          ],
        }
      }
    end

    def elastic_price_facets_for(key)
      {
        "size" => 500,
        "range" => {
          "field" => key,
          "ranges" => [
            {                            },
            { "from"  => -1, "to" => 0 },
            { "from"  => 0, "to"  => 1 },
            { "from"  => 1, "to"  => 5000 },
            { "from"  => 5000, "to"  => 10000 },
            { "from"  => 10000, "to"  => 25000 },
            { "from"  => 25000, "to"  => 50000 },
            { "from"  => 50000, "to"  => 500000 },
            { "from"  => 500000, "to"  => 1000000 },
            { "from"  => 1000000, "to"  => 2000000 },
          ],
        }
      }
    end

    def elastic_facets_hash
      all_terms = true

      return {} if get_param(:no_facets, :boolean)

      get_param(:zero_facets, :string) { |v| all_terms = v.to_bool }

      {
        "space_lock"         => elastic_term_facets_for("space_lock", all_terms),
        "time_lock"          => elastic_term_facets_for("time_lock", all_terms),
        "topic_id"           => elastic_term_facets_for("topic_id", all_terms),
        "provider_id"        => elastic_term_facets_for("library_id", all_terms),
        "product_type_name"  => elastic_term_facets_for("product_type_name", all_terms),
        "price_filter"       => elastic_price_facets_for("price_in_cents"),
        "start_date_local"   => elastic_started_at_facets_for("started_at"),
      }
    end

    def elastic_search_query
      query = []
      keyword = ""
      autocomplete = false

      get_param(:keyword) { |v| keyword = v }
      get_param(:autocomplete) { |v| autocomplete = v }

      return [autocomplete_elastic_search_query_for(keyword)] if autocomplete

      if keyword.present?
        if skill = Skill.from_search(keyword, cache: true, db: false)
          query << nested_elastic_query_for(skill.id)
        end

        keywords = get_keywords(skill, keyword)

        keywords = keywords.compact.collect do |k|
        "#{k.to_s.strip.gsub("/", " ")}"
        end.join(" OR ")

        query << function_structured_query(string_elastic_query_for(keywords))
      else
        query << nested_elastic_query_for(0) unless @options[:nested_query] == 'ignore'
        query << function_structured_query(string_elastic_query_for_default)
      end

      query
    end

    def elastic_inner_filters
      filters = []

      filters << filters_elastic_query_for(:partner_id, @options[:partner].following_partner_ids) if @options[:partner].present?

      filters
    end

    def elastic_outer_filters
      filters = []

      min_price, max_price = nil

      get_param(:course_type_id,   :integers)      { |v| filters << filters_elastic_query_for(:course_type_id, v) }
      get_param(:library_id,       :integers)      { |v| filters << filters_elastic_query_for(:library_id, v) }
      get_param(:providers,        :integers)      { |v| filters << filters_elastic_query_for(:library_id, v) }
      get_param(:topic_id,       :integers)        { |v| filters << filters_elastic_query_for(:topic_id, v) }
      get_param(:article_id,       :integers)      { |v| filters << filters_elastic_query_for(:article_id, v) }
      get_param(:partner_id,       :integers)      { |v| filters << filters_elastic_query_for(:partner_id, v) }
      get_param(:topic_ids,      :integers)        { |v| filters << filters_elastic_query_for(:topic_id, v) }
      get_param(:uuids,            :strings)       { |v| filters << filters_elastic_query_for(:uuid, v) }
      get_param(:ilc)                              { |v| filters << filter_elastic_query_for(:online, true) }
      get_param(:date,             :range)         { |v| filters << filter_elastic_range_query_for(:date, Date.today, v.days.since.to_date, type: :date) }
      get_param(:price,            :float_range)   { |v| filters << filter_elastic_range_query_for(:price, v.first, v.last) }
      get_param(:price_filter,     :float_range)   { |v| min_price = v.first;max_price = v.last }
      get_param(:min_price,            :float)  { |v| min_price = v }
      get_param(:max_price,            :float)  { |v| max_price = v }

      if min_price.present? || max_price.present?
        if min_price == max_price
          filters << filter_elastic_query_for(:price_in_cents, (min_price * 100).to_i)
        else
          filters << filter_elastic_cents_range_query_for(:price_in_cents, min_price, max_price)
        end
      end

      get_param(:slug,             :string)        { |v| filters << filter_elastic_query_for(:slug, v) }
      get_param(:id,               :integer)       { |v| filters << filter_elastic_query_for(:id, v) }
      get_param(:internal_id,      :integer)       { |v| filters << filter_elastic_query_for(:id, v) }
      get_param(:library_db_name,  :string)        { |v| filters << filter_elastic_query_for("library_db_name", v) }
      get_param(:created_at,       :range)         { |v| filters << filter_elastic_range_query_for(:created_at, *v) }
      get_param(:created_date,     :range)         { |v| filters << filter_elastic_range_query_for(:created_at, *v) }
      get_param(:updated_at,       :range)         { |v| filters << filter_elastic_range_query_for(:updated_at, *v) }

      get_param(:deleted, type: :string, default: 'false') do |v|
        filters << filter_elastic_query_for(:deleted, v.to_bool) unless v == 'all'
      end

      get_param(:search_active, type: :string, default: 'true') do |v|
        filters << filter_elastic_query_for(:search_active, v.to_bool) unless v == 'ignore'
      end

      get_param(:live) do |v|
        if v.to_bool == true
          filters << filter_elastic_range_query_for(:date, 10.days.ago, nil, type: :date)
        else
          filters << filter_elastic_range_query_for(:date, nil, 10.days.ago, type: :date)
        end
      end

      get_param(:time_lock, type: :string) do |v|
        filters << filter_elastic_query_for(:time_lock, v) unless v == "B"
      end

      get_param(:days, :string) do |v|
        filter_date = v.split(',').last.to_i.days.since.to_date
        filters << filter_elastic_range_query_for(:started_at, Time.now.utc.to_date, filter_date, type: :date) unless @params_meta[:time_lock][:used] == "B"
      end

      get_param(:manually_collected, :boolean) { |v| filters << filter_elastic_query_for(:manually_collected, v) }

      get_param(:space_lock, type: :string) do |v|
        filters << filter_elastic_query_for(:space_lock, v) unless v == 'B'
      end

      get_param(:status, type: :string) do |v|
        filters << filter_elastic_query_for(:status, v)
      end

      get_param(:product_types, :integers) { |v| filters << filters_elastic_query_for(:course_type_id, v) }

      filters
    end

    def elastic_sort_fields
      [
        "id", "title.raw", "active", "price", "imported_at", "created_at", "rating_count", "average_rating", "status"
      ]
    end

  end

end
