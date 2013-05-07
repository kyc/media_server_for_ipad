require 'rubygems'
require 'sinatra'
require 'open-uri'
require 'json'
require 'find'
require 'ostruct'
require 'srt'
require 'base64'

configure do
  set :public_folder      , Proc.new { File.join(root, "static") }
  set :subtitle_folder    , Proc.new { File.join(root, "static", "subtitle") }
  set :cache_folder       , Proc.new { File.join(root, "static", "cache") }
  set :video_ext_types    , %w{.mkv .rmvb .mp4}
  set :subtitle_ext_types , %w{.srt}
  set :job                , OpenStruct.new(:video => '',:video_name => '',:subtitle => '')
  set :vtt                , Proc.new { File.join(root, "static", "cache","subtitle.vtt") }
  set :ffmpeg_path        , '/usr/local/bin/ffmpeg'
  set :cookie             , File.expand_path('~') + '/' + '.xunlei.lixian.cookies'
  set :gdriveid           , File.new(settings.cookie,'r').each_line.find{|line| line =~ /gdriveid/}.split(';').first.split('=').last
end

helpers do

  def partial (template, locals = {})
    erb(template, :layout => false, :locals => locals)
  end
  
  def get_xunlei_file(file_name=nil)
    cmd = "lx list mkv mp4 --dcid -gcid --download-url"
    cmd += " | grep #{file_name}" if  file_name
    stdout_str       = `#{cmd}` 
    keys             = %w{no name status dcid gcid url}
    xunlei_file_list = stdout_str.force_encoding('utf-8').each_line.map{|line| Hash[keys.zip(line.split(' '))]}.select{|file| file['status'] == 'completed'}.sort_by{|file| file['no'].to_i * -1}
  end

  def prepare_subtitle
    webvtt_lines = []
    webvtt_lines << %{WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:900000. LOCAL:00:00:00.000}
    
    unless settings.job.subtitle.empty?
      subtitle_file = File.new(settings.job.subtitle, "r").read
      SRT::File.parse(subtitle_file).lines.sort_by{ |line| line.start_time}.uniq{|line| line.start_time}.each do |line|
        webvtt_lines << "#{srt_line_to_webvtt(line)}"
      end
    else
      webvtt_lines << "00:00:02.090 --> 02:00:00.000 vertical:lr align:end\n -"
    end 
    file=File.new(settings.vtt, "w")
    file.write(webvtt_lines.compact.join("\n\n"))
    file.close 
  end

  def srt_line_to_webvtt(line)
    text = line.text.join("\n").gsub(/^{.*}/,'').gsub(/<\/?[^>]*>/, "")
    
    if text.scan(/\d\d\d/).size >= 5
      return nil
    else
      time_srt = line.time_str.gsub(',','.')
      return [time_srt,text].join("\n")
    end
  end
  
  def get_subtitle(gcid,dcid)
    xunlei_url  = "http://i.vod.xunlei.com/subtitle/list?gcid=#{gcid}&cid=#{dcid}&userid=153322167"
    subtitles   = JSON.parse(open(xunlei_url).read)['sublist']
    
    begin
      subtitle  = subtitles.select{|sub| sub['sname'] =~ /srt$/i}.select{|sub| sub['sname'] =~ /[\u4e00-\u9fa5]|ch/i}[0]
      filename  = params[:name].sub(/(#{settings.video_ext_types.join('|')})$/i,'.srt')
      File.new(settings.subtitle_folder + '/' + filename,'wb').write(open(subtitle['surl']).read) if subtitle['surl']
      return filename
    rescue Exception => e
      logger.info "subtitle not find!"
      return nil
    end
    
  end

  def gen_m3u8
    if settings.job.video
      
      cmd_step_1  = "cd #{settings.cache_folder}"
      cmd_step_2  = "printf -v cookie 'Cookie: gdriveid=#{settings.gdriveid}\\r\\n'"
      cmd_step_3  = "#{settings.ffmpeg_path} -headers \"$cookie\" -i \"#{Base64.decode64(settings.job.video)}\" -c:v copy -vbsf h264_mp4toannexb -c:a libaac -map 0:0 -map 0:1 -f segment -segment_time 10 -segment_list movie.m3u8 -segment_format mpegts stream%05d.ts"
      movie_cmd   = cmd_step_1 + ';' + cmd_step_2 + ';' + cmd_step_3
  
      begin
        system('killall ffmpeg')
        system("cd #{settings.cache_folder};rm -rf *.ts")
      rescue Exception => e
        logger.info e
      end
      
      Process.spawn(movie_cmd)
      sleep 15
    end
  end
  
end

before %r{.+\.json$} do
  content_type 'application/json'
end

before /add_to_job/ do

  if params[:type] == 'video'
    settings.job  = OpenStruct.new(:video => '',:video_name => '',:subtitle => '')
    exist_file = File.join(settings.subtitle_folder, params[:name].sub(/(#{settings.video_ext_types.join('|')})$/i,'.srt'))
    unless File.exists?(exist_file)
      xunlei_file = get_xunlei_file(params[:name])[0]
      subtitle    = get_subtitle(xunlei_file['gcid'],xunlei_file['dcid'])
      if subtitle
        logger.info File.join(settings.subtitle_folder, subtitle)
        params.merge!(:subtitle => File.join(settings.subtitle_folder, subtitle))
      else
        return nil
      end
    else
      params.merge!(:subtitle => exist_file)
    end
  end
end


get '/' do
  erb "home"
end

get '/play' do
  sub=prepare_subtitle
  gen_m3u8
  erb :play
end

get '/get_xunlei_subtitle' do  
  subtitle = get_subtitle(params[:gcid],params[:dcid])
  
  redirect '/subtitle'
end

get '/xunlei' do
  @xunlei_files = get_xunlei_file
  
  erb :xunlei
end 

get '/subtitle' do
  @subtitle_files = Find.find(settings.subtitle_folder).select{ |path| path =~ /(#{settings.subtitle_ext_types.join('|')})$/i}
  
  erb :subtitle
end

get '/job' do
  @job = settings.job
  
  erb :job
end

get '/clean_job' do
  settings.job  = OpenStruct.new(:video => '',:video_name => '',:subtitle => '')
  
  redirect  '/job' 
end

get '/add_to_job' do
  @job = settings.job

  case params[:type]
  when 'video'
    @job.video      = settings.job.video      = params[:file]
    @job.video_name = settings.job.video_name = params[:name]
    @job.subtitle = settings.job.subtitle     = params[:subtitle] if params[:subtitle]
  when 'subtitle'
    @job.subtitle = settings.job.subtitle = params[:file]
  end
  
  erb :job 
end

get '/task' do
  erb :task
end

post '/task' do
  url = params[:url]
  system("lx add #{url}")
  redirect '/xunlei'
end