# frozen_string_literal: true
require "nokogiri"
require "uri"
require "jekyll"
require "pathname"

root = Pathname.new("_site").expand_path
abort "Build _site first" unless root.directory?
errors = []
pages = root.glob("**/*.html")
config = File.read("_config.yml")
site_url = config[/^url: "([^"]+)"/, 1]
site_host = URI(site_url).host
pages.each do |page|
  document = Nokogiri::HTML(page.read)
  errors << "#{page}: missing title or main" if document.at_css("title").nil? || document.at_css("main").nil?
  document.css("a[href], img[src], link[href], script[src]").each do |element|
    link = element["href"] || element["src"]
    next if link.nil? || link.empty?
    begin
      uri = URI.parse(link.gsub(/[^\x00-\x7F]/) { |c| c.bytes.map { |b| "%%%02X" % b }.join })
    rescue URI::InvalidURIError
      errors << "#{page}: invalid URL #{link}"
      next
    end
    next if uri.host && uri.host != site_host
    next if uri.scheme && !%w[http https].include?(uri.scheme)
    path = URI::DEFAULT_PARSER.unescape(uri.path || "")
    target = if path.empty?
               page
             elsif path.start_with?("/")
               root.join(path.delete_prefix("/"))
             else
               page.dirname.join(path)
             end
    target = target.join("index.html") if target.directory?
    unless target.file?
      errors << "#{page.relative_path_from(root)}: missing #{link}"
      next
    end
    if uri.fragment && target.extname == ".html"
      fragment = URI::DEFAULT_PARSER.unescape(uri.fragment)
      other = target == page ? document : Nokogiri::HTML(target.read)
      errors << "#{page.relative_path_from(root)}: missing anchor #{link}" unless fragment.empty? || other.css("[id], a[name]").any? { |n| n["id"] == fragment || n["name"] == fragment }
    end
  end
end
feed = Nokogiri::XML(root.join("feed.xml").read)
entries = feed.xpath("//*[local-name()='entry']")
Jekyll::PluginManager.require_from_bundler
site = Jekyll::Site.new(Jekyll.configuration("quiet" => true))
site.reset
site.read
post_count = [site.posts.docs.length, site.config.dig("feed", "posts_limit") || 10].min
errors << "Expected #{post_count} feed entries, found #{entries.length}" unless entries.length == post_count
%w[README.md Gemfile Gemfile.lock script/verify-site.rb].each do |file|
  errors << "Development file published: #{file}" if root.join(file).exist?
end
abort errors.join("\n") unless errors.empty?
puts "Verified #{pages.length} HTML pages, local links/assets/anchors, and #{entries.length} articles in RSS."
