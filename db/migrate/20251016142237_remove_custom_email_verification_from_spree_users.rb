class RemoveCustomEmailVerificationFromSpreeUsers < ActiveRecord::Migration[7.1]
  def change
    remove_column :spree_users, :email_verified, :boolean
    remove_column :spree_users, :email_verification_token, :string
    remove_column :spree_users, :email_verification_sent_at, :datetime
  end
end
