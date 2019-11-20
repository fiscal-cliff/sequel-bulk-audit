require "sequel/plugins/bulk_audit/version"
require 'sequel/model'

module Sequel
  module Plugins
    module BulkAudit
      class << self
        def apply(model, opts={})
          model.instance_eval do
            @excluded_columns = [*opts[:excluded_columns]]
          end
        end

        def model_to_table_map
          @model_to_table_map ||= ObjectSpace.each_object(Sequel::Model.singleton_class).select do |klazz|
            next if klazz.name.nil?
            klazz < Sequel::Model && klazz&.plugins&.include?(Sequel::Plugins::BulkAudit)
          end.map { |c| [c.to_s, c.table_name] }.to_h.invert
        end
      end

      module SharedMethods
        def with_current_user(current_user, attributes = nil)
          db.transaction do
            trid = db.select(Sequel.function(:txid_current)).single_value
            data = db.select(Sequel.expr(current_user&.id || 0).as(:user_id),
                             Sequel.cast(current_user&.login || "unspecified", :text).as(:username),
                             Sequel.pg_jsonb(Sequel::Plugins::BulkAudit.model_to_table_map).as(:model_map),
                             Sequel.pg_jsonb(attributes || {}).as(:data))
            db.create_table!(:"__audit_info_#{trid}", temp: true, as: data, on_commit: :drop)
            result = yield if block_given?
            result
          end
        end
      end

      module ClassMethods
        include SharedMethods
      end

      module InstanceMethods
        include SharedMethods
      end
    end
  end
end
