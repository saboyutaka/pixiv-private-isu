require 'app'

app = Isuconp::App.new

FileUtils.mkdir_p(image_dir) unless FileTest.exist?(image_dir)

posts = app.helpers.db.query('select * from posts')
posts.each do |post|
  path = "../public#{app.helpers.image_url(post)}"
  File.write(path, post[:imgdata])
end
