require 'active_record'
require "bulk_uploadable/version"

module BulkUploadable
  # Your code goes here...

  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def bulk_upload(keys, values, use_transaction = false)
      sql_columns = "(#{keys.join(', ')})"

      escaped_values =  values.collect do |value|
        value.collect {|v| sanitize(v) }
      end

      sql_values = escaped_values.collect do |value|
        "(#{value.join(', ')})"
      end.join(', ')

      sql_query = "INSERT INTO #{self.table_name} #{sql_columns} VALUES #{sql_values}"

      if use_transaction
        self.perform_sql_in_transaction sql_query
      else
        self.perform_sql sql_query
      end
    end

    def perform_sql(sql)
      self.connection.execute(sql)
    end

    def perform_sql_in_transaction(sql)
      stmt_result = nil
      self.transaction do
        stmt_result = self.connection.execute(sql).to_a
      end
    end
  end
end
