namespace :solidus do
    desc "Copy all Solidus models to app/models for customization"
    task :copy_models => :environment do
      gem_path = Gem.loaded_specs['solidus_core'].full_gem_path
      source_dir = File.join(gem_path, 'app', 'models')
      target_dir = Rails.root.join('app', 'models')
      
      if Dir.exist?(source_dir)
        FileUtils.cp_r("#{source_dir}/.", target_dir)
        puts "✅ Copied all Solidus models to #{target_dir}"
        puts "📝 You can now customize these models directly!"
      else
        puts "❌ Could not find Solidus models directory"
      end
    end
  end