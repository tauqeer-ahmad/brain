class Institution < ApplicationRecord
  searchkick

  include AASM
  include SearchWrapper

  has_many :administrators

  has_attached_file :logo,
                    styles: {
                      medium: '300x300!',
                      thumb: '100x100>'
                    }
  validates_attachment_content_type :logo, content_type: /\Aimage\/.*\z/

  after_create :add_tenant_to_apartment, :add_indexes

  validates :name, presence: { message: "Name field is required" }
  validates :location, presence: { message: "Location field is required" }
  validates :city, presence: { message: "City must be selected" }
  validates :country, presence: { message: "Country must be selected" }
  validates :sector, presence: { message: "Sector must be selected" }
  validates :subdomain, presence: { message: "subdomain must be selected" }
  validates :subdomain, uniqueness: { message: "Subdomain already selected" }

  SECTORS = %w(public private)
  LEVELS = %w(high middle primary olevel alevel)

  aasm :requires_lock => true, :column => 'status' do
    state :pending, :initial => true
    state :active, :locked

    event :pending do
      transitions :to => :pending
    end

    event :active do
      transitions :from => [:pending, :locked], :to => :active
    end

    event :locked do
      transitions :from => [:pending, :active], :to => :locked
    end
  end

  def search_data
    {
      name: name,
      location: location,
      city: city,
      country: country,
      description: description,
      sector: sector,
      level: level,
    }
  end

  def display_created_at
    created_at.strftime("%d, %B %Y %H:%M %p")
  end

  def display_status
    status.to_s.capitalize
  end

  def country_name
    country_code = ISO3166::Country[country]
    country_code.translations[I18n.locale.to_s] || country_code.name
  end

  def self.current
    tenant = Institution.find_by subdomain: Apartment::Tenant.current
    raise ::Apartment::TenantNotFound, "Unable to find tenant" unless tenant
    tenant
  end

  def switch!
    Apartment::Tenant.switch! subdomain
  end

  private
    def add_tenant_to_apartment
      Apartment::Tenant.create(subdomain)
    end

    def drop_tenant_from_apartment
      Apartment::Tenant.drop(subdomain)
    end

    def add_indexes
      Apartment::Tenant.switch!(subdomain)

      SEARCHKICK_MODELS.each do |model|
        next if model.in? Apartment::excluded_models
        model.constantize.reindex
      end

      Apartment::Tenant.switch!('public')
    end
end
