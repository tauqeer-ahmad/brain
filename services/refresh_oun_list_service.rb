require 'open-uri'
class RefreshOunListService
  attr_accessor :nodes, :list_items
  def initialize
    @list_items = []
    @nodes = ['//INDIVIDUAL', '//ENTITY']
  end

  def call
    p 'Truncating tables........'
    ActiveRecord::Base.connection.execute('TRUNCATE oun_entries CASCADE')
    ActiveRecord::Base.connection.execute('TRUNCATE oun_aliases CASCADE')
    parse_and_load_xml_data
  end

  def get_un_sc_list_xml
    xml = open('https://scsanctions.un.org/resources/xml/en/consolidated.xml')
    Nokogiri::XML(xml)
  end

  def parse_and_load_xml_data
    p 'Parsing OUN list xml.........'
    data_file = get_un_sc_list_xml
    nodes.each do |node|
      data_file.xpath(node).each do |item|
        node_type = node.split('/')[2]

        item_data = {
          node_type: node_type,
          identifier: item.xpath('DATAID').text.strip,
          first_name: item.xpath('FIRST_NAME').text.strip,
          second_name: item.xpath('SECOND_NAME').text.strip,
          third_name: item.xpath('THIRD_NAME').text.strip,
          fourth_name: item.xpath('FOURTH_NAME').text.strip,
          name_original_script: item.xpath('NAME_ORIGINAL_SCRIPT').text.strip,
          listed_on: item.xpath('LISTED_ON').text.strip,
          titles: fetch_titles(item),
          designations: fetch_designations(item),
          dobs: fetch_dobs(item),
          pobs: fetch_pobs(item),
          nationalities: fetch_nationalities(item),
          documents: fetch_documents(item),
          addresses: fetch_addresses(item, "#{node_type}_ADDRESS"),
          version_number: item.xpath('VERSIONNUM').text.strip,
          un_list_type: item.xpath('UN_LIST_TYPE').text.strip,
          reference_number: item.xpath('REFERENCE_NUMBER').text.strip,
          comments: item.xpath('COMMENTS1').text.strip,
          last_day_updated: fetch_last_day_updates(item)
        }

        list_item = OunEntry.new(item_data)

        build_aliases(item, list_item, "#{node_type}_ALIAS")

        list_items << list_item
      end
    end

    p 'Loading records to Database'
    OunEntry.import list_items, recursive: true
  end

  def fetch_titles(item)
    titles = []
    item.xpath('TITLE/VALUE').each do |value|
      title = { value: value.text.strip }
      titles << title
    end

    titles
  end

  def fetch_designations(item)
    designations = []
    item.xpath('DESIGNATION/VALUE').each do |value|
      designation = { value: value.text.strip }
      designations << designation
    end

    designations
  end

  def fetch_dobs(item)
    dobs = []
    item.xpath('INDIVIDUAL_DATE_OF_BIRTH').each do |dob|
      dob_obj = {
        dob_type: dob.xpath('TYPE_OF_DATE').text.strip,
        date: dob.xpath('DATE').text.strip,
        note: dob.xpath('NOTE').text.strip,
        year: dob.xpath('YEAR').text.strip,
        from_year: dob.xpath('FROM_YEAR').text.strip,
        to_year: dob.xpath('TO_YEAR').text.strip
      }

      dobs << dob_obj
    end

    dobs
  end

  def fetch_pobs(item)
    pobs = []
    item.xpath('INDIVIDUAL_PLACE_OF_BIRTH').each do |item_pob|
      pob = {
        city: item_pob.xpath('CITY').text.strip,
        country: item_pob.xpath('COUNTRY').text.strip,
        state_province: item_pob.xpath('STATE_PROVINCE').text.strip
      }

      pobs << pob
    end

    pobs
  end

  def fetch_nationalities(item)
    nationalities = []
    item.xpath('NATIONALITY/VALUE').each do |nationality_value|
      nationality = { value: nationality_value.text.strip }
      nationalities << nationality
    end

    nationalities
  end

  def fetch_documents(item)
    documents = []
    item.xpath('INDIVIDUAL_DOCUMENT').each do |item_document|
      document = {
        document_type1: item_document.xpath('TYPE_OF_DOCUMENT').text.strip,
        document_type2: item_document.xpath('TYPE_OF_DOCUMENT2').text.strip,
        number: item_document.xpath('NUMBER').text.strip,
        issuing_country: item_document.xpath('ISSUING_COUNTRY').text.strip,
        date_of_issue: item_document.xpath('DATE_OF_ISSUE').text.strip,
        country_of_issue: item_document.xpath('COUNTRY_OF_ISSUE').text.strip,
        note: item_document.xpath('NOTE').text.strip
      }

      documents << document
    end

    documents
  end

  def fetch_addresses(item, node_name)
    addresses = []
    item.xpath(node_name).each do |item_address|
      address = {
        street: item_address.xpath('STREET').text.strip,
        city: item_address.xpath('CITY').text.strip,
        country: item_address.xpath('COUNTRY').text.strip,
        note: item_address.xpath('NOTE').text.strip,
        state_province: item_address.xpath('STATE_PROVINCE').text.strip
      }

      addresses << address
    end

    addresses
  end

  def build_aliases(item, list_item, node_name)
    item.xpath(node_name).each do |item_alias|
      name = item_alias.xpath('ALIAS_NAME').text.strip
      next if name.blank?
      entry = {
        name: name,
        quality: item_alias.xpath('QUALITY').text.strip
      }

      list_item.oun_aliases.build(entry)
    end

    list_item
  end

  def fetch_last_day_updates(item)
    last_day_updates = []
    item.xpath('LAST_DAY_UPDATED/VALUE').each do |update_value|
      last_day_update = { value: update_value.text.strip }
      last_day_updates << last_day_update
    end

    last_day_updates
  end
end
