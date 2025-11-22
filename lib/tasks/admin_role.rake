namespace :admin do
  desc "Grant admin role to a user"
  task :grant_role, [:email] => :environment do |t, args|
    email = args[:email]
    
    if email.blank?
      puts "Please provide an email address. Usage: bin/rails admin:grant_role[email@example.com]"
      next
    end

    user = Spree::User.find_by(email: email)
    
    if user.nil?
      puts "User with email '#{email}' not found."
      next
    end

    admin_role = Spree::Role.find_or_create_by(name: 'admin')
    
    if user.spree_roles.include?(admin_role)
      puts "User '#{email}' already has the admin role."
    else
      user.spree_roles << admin_role
      if user.save
        puts "Successfully granted admin role to '#{email}'."
      else
        puts "Failed to grant role: #{user.errors.full_messages.join(', ')}"
      end
    end
  end
end

