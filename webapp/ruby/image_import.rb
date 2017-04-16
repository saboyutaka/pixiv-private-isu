require './app'

app = Isuconp::App.new

image_dir = '../public/image'
FileUtils.mkdir_p(image_dir) unless FileTest.exist?(image_dir)

post_ids = app.helpers.db.query('select id from posts').to_a.map {|h| h[:id] }
post_ids.each do |post_id|
  print '.'
  post = post = app.helpers.db.query("select * from posts where id = #{post_id } limit 1").first
  path = "../public#{app.helpers.image_url(post)}"
  File.write(path, post[:imgdata]) unless FileTest.exist?(path)
end
puts ''
puts 'finish'
