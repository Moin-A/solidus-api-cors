class AddVerificationFieldsToSpreeUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :spree_users, :email_verified, :boolean, default: false, null: false
    add_column :spree_users, :phone_verified, :boolean, default: false, null: false
    add_column :spree_users, :email_verification_token, :string
    add_column :spree_users, :phone_verification_token, :string
    add_column :spree_users, :phone_number, :string
    add_column :spree_users, :email_verification_sent_at, :datetime
    add_column :spree_users, :phone_verification_sent_at, :datetime

    # Add indexes for verification lookups
    add_index :spree_users, :email_verification_token, unique: true
    add_index :spree_users, :phone_verification_token, unique: true
    add_index :spree_users, :phone_number
  end
end
