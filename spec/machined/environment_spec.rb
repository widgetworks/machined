require "spec_helper"

describe Machined::Environment do
  describe "#initialize" do
    it "loads configuration from a config file" do
      within_construct do |c|
        c.file "machined.rb", <<-CONTENT.unindent
          config.output_path = "site"
          append_sprocket :updates
        CONTENT
        machined.config.output_path.should == "site"
        machined.updates.should be_a(Machined::Sprocket)
      end
    end
  end
  
  describe "#append_sprocket" do
    it "creates a new Sprockets environment" do
      sprocket = machined.append_sprocket :updates
      sprocket.should be_a(Sprockets::Environment)
    end
    
    it "appends the sprocket to #sprockets" do
      sprocket = machined.append_sprocket :updates
      machined.sprockets.last.should be(sprocket)
    end
    
    it "adds a method with the given name which returns the sprocket" do
      sprocket = machined.append_sprocket :updates
      machined.updates.should be(sprocket)
      Machined::Environment.method_defined?(:updates).should be_false
    end
    
    it "yields the sprocket for configuration" do
      yielded_sprocket = nil
      sprocket = machined.append_sprocket :updates do |updates|
        yielded_sprocket = updates
      end
      yielded_sprocket.should be(sprocket)
    end
    
    it "initializes the sprocket with a reference to the Machined environment" do
      sprocket = machined.append_sprocket :updates
      sprocket.machined.should be(machined)
    end
    
    it "initializes the sprocket with configuration" do
      sprocket = machined.append_sprocket :updates, :root => "spec/machined"
      sprocket.root.should == File.expand_path("spec/machined")
    end
  end
  
  describe "#prepend_sprocket" do
    it "creates a new Sprockets environment" do
      sprocket = machined.prepend_sprocket :updates
      sprocket.should be_a(Sprockets::Environment)
    end
    
    it "prepends the sprocket to #sprockets" do
      sprocket = machined.prepend_sprocket :updates
      machined.sprockets.first.should be(sprocket)
    end
  end
  
  describe "#helpers" do
    it "adds methods defined in the given block to the Context" do
      machined.helpers do
        def hello
          "world"
        end
      end
      
      context.hello.should == "world"
    end
    
    it "adds methods defined in the given module to the Context" do
      helper = Module.new do
        def hello
          "world"
        end
      end
      machined.helpers helper
      context.hello.should == "world"
    end
  end
  
  describe "default assets sprocket" do
    it "appends the standard asset paths" do
      within_construct do |c|
        c.directory "assets/images"
        c.directory "assets/javascripts"
        c.directory "assets/stylesheets"
        c.directory "vendor/assets/images"
        c.directory "vendor/assets/javascripts"
        c.directory "vendor/assets/stylesheets"
        
        machined.assets.paths.should match_paths(%w(
          assets/images
          assets/javascripts
          assets/stylesheets
          vendor/assets/images
          vendor/assets/javascripts
          vendor/assets/stylesheets
        )).with_root(c)
      end
    end
    
    it "appends the available asset paths" do
      within_construct do |c|
        c.directory "assets/css"
        c.directory "assets/img"
        c.directory "assets/js"
        c.directory "assets/plugins"
        
        machined.assets.paths.should match_paths(%w(
          assets/css
          assets/img
          assets/js
          assets/plugins
        )).with_root(c)
      end
    end
    
    it "appends Rails::Engine paths" do
      require "rails"
      require "jquery-rails"
      machined.assets.paths.first.should =~ %r(/jquery-rails-[\d\.]+/vendor/assets/javascripts)
      Rails::Engine.subclasses.delete Jquery::Rails::Engine
    end
    
    it "appends Sprockets::Plugin paths" do
      require "sprockets-plugin"
      
      within_construct do |c|
        plugin_dir = c.directory "plugin/assets"
        plugin_dir.directory "images"
        plugin_dir.directory "javascripts"
        plugin_dir.directory "stylesheets"
        
        plugin = Class.new(Sprockets::Plugin)
        plugin.append_paths_in plugin_dir
        
        machined.assets.paths.should match_paths(%w(
          plugin/assets/images
          plugin/assets/javascripts
          plugin/assets/stylesheets
        )).with_root(c)
        Sprockets::Plugin.plugins.delete plugin
      end
    end
    
    it "compiles web assets" do
      within_construct do |c|
        c.file "assets/javascripts/main.js",       "//= require dep"
        c.file "assets/javascripts/dep.js",        "var app = {};"
        c.file "assets/stylesheets/main.css.scss", "@import 'dep';\nbody { color: $color; }"
        c.file "assets/stylesheets/_dep.scss",     "$color: red;"
        
        machined.assets["main.js"].to_s.should == "var app = {};\n"
        machined.assets["main.css"].to_s.should == "body {\n  color: red; }\n"
      end
    end
  end
  
  describe "default pages sprocket" do
    it "appends the pages path" do
      within_construct do |c|
        c.directory "pages"
        machined.pages.paths.should match_paths(%w(pages)).with_root(c)
      end
    end
    
    it "compiles html pages" do
      within_construct do |c|
        c.file "pages/index.html.haml", "%h1 Hello World"
        machined.pages["index.html"].to_s.should == "<h1>Hello World</h1>\n"
      end
    end
  end
  
  describe "default views sprocket" do
    it "appends the views path" do
      within_construct do |c|
        c.directory "views"
        machined.views.paths.should match_paths(%w(views)).with_root(c)
      end
    end
    
    it "compiles html pages" do
      within_construct do |c|
        c.file "views/layouts/main.html.haml", "%h1 Hello World"
        machined.views["layouts/main.html"].to_s.should == "<h1>Hello World</h1>\n"
      end
    end
  end
  
  describe "compression" do
    context "with compress set to true" do
      it "compresses javascripts and stylesheets" do
        within_construct do |c|
          c.file "assets/javascripts/main.js",       "//= require dep"
          c.file "assets/javascripts/dep.js",        "var app = {};"
          c.file "assets/stylesheets/main.css.scss", "@import 'dep';\nbody { color: $color; }"
          c.file "assets/stylesheets/_dep.scss",     "$color: red;"
          
          Crush::Uglifier.should_receive(:compress).with("var app = {};\n").and_return("compressed")
          Crush::Sass::Engine.should_receive(:compress).with("body {\n  color: red; }\n").and_return("compressed")
          
          machined :compress => true
          machined.assets["main.js"].to_s.should == "compressed"
          machined.assets["main.css"].to_s.should == "compressed"
        end
      end
    end
  end
  
  context "with a js_compressor set" do
    it "compresses using that compressor" do
      within_construct do |c|
        c.file "assets/javascripts/main.js", "var app = {};"
        c.file "machined.rb", "config.js_compressor = :packr"
        Crush::Packr.should_receive(:compress).with("var app = {};\n").and_return("compressed")
        machined.assets["main.js"].to_s.should == "compressed"
      end
    end
  end
end
