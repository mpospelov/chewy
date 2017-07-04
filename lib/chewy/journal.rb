require 'chewy/journal/entry'
require 'chewy/journal/query'
require 'chewy/journal/apply'
require 'chewy/journal/clean'

module Chewy
  class Journal
    JOURNAL_MAPPING = {
      journal: {
        properties: {
          index_name: {type: 'keyword'},
          type_name: {type: 'keyword'},
          action: {type: 'keyword'},
          object_ids: {type: 'keyword'},
          created_at: {type: 'date'}
        }
      }
    }.freeze

    def initialize(type)
      @entries = []
      @type = type
    end

    def add(action_objects)
      @entries.concat(action_objects.map do |action, objects|
        next if objects.blank?

        {
          index_name: @type.index.derivable_name,
          type_name: @type.type_name,
          action: action,
          object_ids: identify(objects),
          created_at: Time.now.to_i
        }
      end.compact)
    end

    def bulk_body
      @entries.map do |record|
        {
          index: {
            _index: self.class.index_name,
            _type: self.class.type_name,
            data: record
          }
        }
      end
    end

  private

    def identify(objects)
      @type.adapter.identify(objects)
    end

    class << self
      def exists?
        Chewy.client.indices.exists? index: index_name
      end

      def index_name
        [
          Chewy.configuration[:prefix],
          Chewy.configuration[:journal_name] || 'chewy_journal'
        ].reject(&:blank?).join('_')
      end

      def type_name
        JOURNAL_MAPPING.keys.first
      end

      def create
        return if exists?
        Chewy.client.indices.create index: index_name, body: {settings: {index: Chewy.configuration[:index]}, mappings: JOURNAL_MAPPING}
        Chewy.wait_for_status
      end

      def delete!
        delete or raise Elasticsearch::Transport::Transport::Errors::NotFound
      end

      def delete
        result = Chewy.client.indices.delete index: index_name
        Chewy.wait_for_status if result
        result
      rescue Elasticsearch::Transport::Transport::Errors::NotFound
        false
      end

      def apply_changes_from(*args)
        Apply.since(*args)
      end

      def entries_from(*args)
        Entry.since(*args)
      end

      def clean_until(*args)
        Clean.until(*args)
      end
    end
  end
end
