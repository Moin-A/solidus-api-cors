namespace :spree_rating do
  namespace :update_spree_rating_user_id do
    desc ""
    task update: :environment do                 
      spree_ratings = Spree::Rating.where("spree_ratings.user_id IS NULL")
      
      spree_ratings.each do |rating|
        user = rating.product.orders.first.user
        rating.user = user if user.present?

        begin
          if rating.save
            puts "Successfully Updated"
          else
            puts "Something went wrong: #{rating.errors.full_messages.join(', ')}"
          end
        rescue => e
          puts "Exception occurred for Rating ##{rating.id}: #{e.message}"
        end
      end
    end
  end
end
