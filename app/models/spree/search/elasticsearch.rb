    # app/models/spree/search/elasticsearch.rb
module Spree
  module Search
    class Elasticsearch < Spree::Core::Search::Base

      # This is called by Solidus to get products
      def retrieve_products
        search_results = if keywords.present?
          elasticsearch_query(keywords)
        else
          # fallback: return all products
          ::Spree::Product.__elasticsearch__.search({ query: { match_all: {} } })
        end

        # Convert ES hits → ActiveRecord relation
        product_ids = search_results.records.ids
        Spree::Product.where(id: product_ids)
      end

      private

      # Build the ES query
      def elasticsearch_query(text)
        ::Spree::Product.__elasticsearch__.search(
          {
            query: {
              bool: {
                must: [
                  {
                    multi_match: {
                      query: text,
                      fields: ["name^3", "description"],
                      fuzziness: "AUTO"
                    }
                  }
                ],
                filter: taxon_filter
              }
            }
          }
        )
      end

      # Handle taxon filtering (optional)
      def taxon_filter
        return [] unless taxon.present?

        [
          {
            term: {
              taxon_ids: taxon.id
            }
          }
        ]
      end
    end
  end
end
