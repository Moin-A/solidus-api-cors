class AddColumnToRating < ActiveRecord::Migration[7.2]
  def change
    add_reference :spree_ratings, :user, foreign_key: {to_table: "spree_users"}, index: {name: 'idx_ratings_on_user_id'}   
  end
end
