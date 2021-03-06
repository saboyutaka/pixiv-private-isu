require 'sinatra/base'
require 'mysql2'
require 'rack-flash'
require 'shellwords'
require 'rack-lineprof'
require 'pry'
require 'pry-doc'
require 'openssl'
require 'tilt/erb'
# require 'logger'

module Isuconp
  class App < Sinatra::Base
    use Rack::Session::Memcache, autofix_keys: true, secret: ENV['ISUCONP_SESSION_SECRET'] || 'sendagaya'
    use Rack::Flash

    # Profiler # TODO
    use Rack::Lineprof

    set :public_folder, File.expand_path('../../public', __FILE__)

    UPLOAD_LIMIT = 10 * 1024 * 1024 # 10mb

    POSTS_PER_PAGE = 20

    helpers do
      def logger
        @logger ||= Logger.new('tmp/sinatra.log')
      end

      def config
        @config ||= {
          db: {
            host: ENV['ISUCONP_DB_HOST'] || 'localhost',
            port: ENV['ISUCONP_DB_PORT'] && ENV['ISUCONP_DB_PORT'].to_i,
            username: ENV['ISUCONP_DB_USER'] || 'root',
            password: ENV['ISUCONP_DB_PASSWORD'] || '',
            database: ENV['ISUCONP_DB_NAME'] || 'isuconp',
            socket: ENV['ISUCON_DB_SOCKET']
          },
        }
      end

      def db
        return Thread.current[:isuconp_db] if Thread.current[:isuconp_db]
        client = Mysql2::Client.new(
          host: config[:db][:host],
          port: config[:db][:port],
          username: config[:db][:username],
          password: config[:db][:password],
          database: config[:db][:database],
          encoding: 'utf8mb4',
          reconnect: true,
        )
        client.query_options.merge!(symbolize_keys: true, database_timezone: :local, application_timezone: :local)
        Thread.current[:isuconp_db] = client
        client
      end

      def db_initialize
        sql = []
        sql << 'DELETE FROM users WHERE id > 1000'
        sql << 'DELETE FROM posts WHERE id > 10000'
        sql << 'DELETE FROM comments WHERE id > 100000'
        sql << 'UPDATE users SET del_flg = 0'
        sql << 'UPDATE users SET del_flg = 1 WHERE id % 50 = 0'
        sql << 'UPDATE posts SET del_flg = 0'
        sql << 'UPDATE posts JOIN users ON posts.user_id = users.id SET posts.del_flg = 1 WHERE users.del_flg = 1'

        sql.each do |s|
          db.query(s)
        end

        # 追加された静的imageを削除
        Dir.glob('../public/image/*').select { |path| path.scan(/\d+/)[0].to_i > 10000 }.each { |path| FileUtils.rm(path) }
      end

      def try_login(account_name, password)
        user = db.query("SELECT * FROM users WHERE account_name = '#{account_name}' AND del_flg = 0").first

        if user && calculate_passhash(user[:account_name], password) == user[:passhash]
          return user
        elsif user
          return nil
        else
          return nil
        end
      end

      def validate_user(account_name, password)
        if !(/\A[0-9a-zA-Z_]{3,}\z/.match(account_name) && /\A[0-9a-zA-Z_]{6,}\z/.match(password))
          return false
        end

        return true
      end

      def digest(src)
        OpenSSL::Digest::SHA512.hexdigest(src)
      end

      def calculate_salt(account_name)
        digest account_name
      end

      def calculate_passhash(account_name, password)
        digest "#{password}:#{calculate_salt(account_name)}"
      end

      def get_session_user()
        if session[:user]
          db.query("SELECT * FROM `users` WHERE `id` = #{session[:user][:id]}").first
        else
          nil
        end
      end

      def make_posts(results, all_comments: false)
        posts = []
        results.to_a.each do |post|
          query = "SELECT `comment`, `account_name` as `user_account_name`
                   FROM `comments`
                   JOIN `users` ON `comments`.`user_id` = `users`.`id`
                   WHERE `post_id` = #{post[:id]}
                   ORDER BY `comments`.`created_at` DESC"
          unless all_comments
            query += ' LIMIT 3'
          end
          comments = db.query(query).to_a
          post[:comments] = comments.reverse

          posts.push(post)
        end

        if posts.any?
          post_ids = posts.map { |h| h[:id] }

          # comment_count
          query = "SELECT post_id, count(1) as count FROM `comments` WHERE `post_id` in (#{post_ids.join(", ")}) group by post_id"
          counts = db.query(query).to_a


          posts.each do |post|
            # comment_count
            c = counts.find { |count| post[:id] == count[:post_id] }
            post[:comment_count] = c ? c[:count] : 0
          end
        end

        posts
      end

      def image_url(post)
        ext = ext_from(post[:mime])
        "/image/#{post[:id]}#{ext}"
      end

      def ext_from(mine)
        if mine == "image/jpeg"
          ".jpg"
        elsif mine == "image/png"
          ".png"
        elsif mine == "image/gif"
          ".gif"
        else
          ""
        end
      end
    end

    # before do
    #   http_headers = request.env.select { |k, v| k.start_with?('HTTP_') }
    #   logger.info http_headers
    # end

    get '/initialize' do
      db_initialize
      return 200
    end

    get '/login' do
      if get_session_user()
        redirect '/', 302
      end
      erb :login, layout: :layout, locals: { me: nil }
    end

    post '/login' do
      if get_session_user()
        redirect '/', 302
      end

      user = try_login(params['account_name'], params['password'])
      if user
        session[:user] = {
          id: user[:id]
        }
        session[:csrf_token] = SecureRandom.hex(16)
        redirect '/', 302
      else
        flash[:notice] = 'アカウント名かパスワードが間違っています'
        redirect '/login', 302
      end
    end

    get '/register' do
      if get_session_user()
        redirect '/', 302
      end
      erb :register, layout: :layout, locals: { me: nil }
    end

    post '/register' do
      if get_session_user()
        redirect '/', 302
      end

      account_name = params['account_name']
      password = params['password']

      validated = validate_user(account_name, password)
      if !validated
        flash[:notice] = 'アカウント名は3文字以上、パスワードは6文字以上である必要があります'
        redirect '/register', 302
        return
      end

      user = db.query("SELECT 1 FROM users WHERE `account_name` = '#{account_name}'").first
      if user
        flash[:notice] = 'アカウント名がすでに使われています'
        redirect '/register', 302
        return
      end

      sql = db.prepare('INSERT INTO `users` (`account_name`, `passhash`) VALUES (?,?)')
      sql.execute(account_name, calculate_passhash(account_name, password))
      session[:user] = { id: db.last_id }
      sql.close

      session[:csrf_token] = SecureRandom.hex(16)
      redirect '/', 302
    end

    get '/logout' do
      session.delete(:user)
      redirect '/', 302
    end

    get '/' do
      me = get_session_user()

      results = db.query("SELECT `posts`.`id`, `account_name` as `user_account_name`, `body`, `posts`.`created_at`, `mime`
                          FROM `posts`
                          JOIN `users`
                          ON `posts`.`user_id` = `users`.`id`
                          WHERE `posts`.`del_flg` = 0
                          ORDER BY `posts`.`created_at` DESC
                          LIMIT #{POSTS_PER_PAGE}")
      posts = make_posts(results)

      erb :index, layout: :layout, locals: { posts: posts, me: me }
    end

    get '/@:account_name' do
      user = db.query("SELECT * FROM `users` WHERE `account_name` = '#{params[:account_name]}' AND `del_flg` = 0").first

      if user.nil?
        return 404
      end

      results = db.query("SELECT `posts`.`id`, `account_name` as `user_account_name`, `body`, `mime`, `posts`.`created_at`
                          FROM `posts`
                          JOIN `users`
                          ON `posts`.`user_id` = `users`.`id`
                          WHERE `user_id` = #{user[:id]}
                          ORDER BY `created_at` DESC")
      posts = make_posts(results)

      comment_count = db.query("SELECT COUNT(*) AS count FROM `comments` WHERE `user_id` = #{user[:id]}").first[:count]

      post_ids = db.query("SELECT `id` FROM `posts` WHERE `user_id` = #{user[:id]}").map { |post| post[:id] }
      post_count = post_ids.length

      commented_count = 0
      if post_count > 0
        commented_count = db.query("SELECT COUNT(*) AS count FROM `comments` WHERE `post_id` IN (#{post_ids.join(",")})").first[:count]
      end

      me = get_session_user()

      erb :user, layout: :layout, locals: { posts: posts, user: user, post_count: post_count, comment_count: comment_count, commented_count: commented_count, me: me }
    end

    get '/posts' do
      max_created_at = params['max_created_at']
      formatted_max_created_at = max_created_at.nil? ? 'NULL' : "'#{Time.iso8601(max_created_at).localtime}'"
      results = db.query("SELECT `posts`.`id`, `account_name` as `user_account_name`, `body`, `mime`, `posts`.`created_at`
                          FROM `posts`
                          JOIN `users`
                          ON `posts`.`user_id` = `users`.`id`
                          WHERE `users`.`del_flg` = 0
                          AND `posts`.`created_at` <= #{formatted_max_created_at}
                          ORDER BY `posts`.`created_at` DESC
                          LIMIT #{POSTS_PER_PAGE}")
      posts = make_posts(results)

      erb :posts, layout: false, locals: { posts: posts }
    end

    get '/posts/:id' do
      results = db.query("SELECT `posts`.`id`, `account_name` as `user_account_name`, `body`, `mime`, `posts`.`created_at`
                          FROM `posts`
                          JOIN `users`
                          ON `posts`.`user_id` = `users`.`id`
                          WHERE `posts`.`id` = #{params[:id]}
                          LIMIT 1")
      posts = make_posts(results, all_comments: true)

      return 404 if posts.length == 0

      post = posts[0]

      me = get_session_user()

      erb :post, layout: :layout, locals: { post: post, me: me }
    end

    post '/' do
      me = get_session_user()

      if me.nil?
        redirect '/login', 302
      end

      if params['csrf_token'] != session[:csrf_token]
        return 422
      end

      if params['file']
        mime = ''
        # 投稿のContent-Typeからファイルのタイプを決定する
        if params["file"][:type].include? "jpeg"
          mime = "image/jpeg"
        elsif params["file"][:type].include? "png"
          mime = "image/png"
        elsif params["file"][:type].include? "gif"
          mime = "image/gif"
        else
          flash[:notice] = '投稿できる画像形式はjpgとpngとgifだけです'
          redirect '/', 302
        end

        if params['file'][:tempfile].size > UPLOAD_LIMIT
          flash[:notice] = 'ファイルサイズが大きすぎます'
          redirect '/', 302
        end

        sql = db.prepare('INSERT INTO `posts` (`user_id`, `mime`, `body`) VALUES (?,?,?)')
        sql.execute(me[:id], mime, params["body"])
        pid = db.last_id
        sql.close

        ext = ext_from(mime)
        path = "../public/image/#{pid}#{ext}"

        FileUtils.cp(params['file'][:tempfile], path)
        FileUtils.chmod(0644, path)
        params['file'][:tempfile].close!

        redirect "/posts/#{pid}", 302
      else
        flash[:notice] = '画像が必須です'
        redirect '/', 302
      end
    end

    post '/comment' do
      me = get_session_user()

      if me.nil?
        redirect '/login', 302
      end

      if params["csrf_token"] != session[:csrf_token]
        return 422
      end

      unless /\A[0-9]+\z/.match(params['post_id'])
        return 'post_idは整数のみです'
      end
      post_id = params['post_id']

      sql = db.prepare('INSERT INTO `comments` (`post_id`, `user_id`, `comment`) VALUES (?,?,?)')
      sql.execute(post_id, me[:id], params['comment'])
      sql.close

      redirect "/posts/#{post_id}", 302
    end

    get '/admin/banned' do
      me = get_session_user()

      if me.nil?
        redirect '/login', 302
      end

      if me[:authority] == 0
        return 403
      end

      users = db.query('SELECT * FROM `users` WHERE `authority` = 0 AND `del_flg` = 0 ORDER BY `created_at` DESC')

      erb :banned, layout: :layout, locals: { users: users, me: me }
    end

    post '/admin/banned' do
      me = get_session_user()

      if me.nil?
        redirect '/', 302
      end

      if me[:authority] == 0
        return 403
      end

      if params['csrf_token'] != session[:csrf_token]
        return 422
      end

      params['uid'].each do |id|
        db.query("UPDATE users SET del_flg = 1 WHERE id = #{id}")
        db.query("UPDATE posts SET del_flg = 1 WHERE user_id = #{id}")
      end

      redirect '/admin/banned', 302
    end
  end
end
