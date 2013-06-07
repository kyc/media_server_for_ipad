# encoding: UTF-8

require 'rubygems'
require 'sinatra'
require 'open-uri'
require 'json'
require 'find'
require 'ostruct'
require 'srt'
require 'base64'
#require 'zip/zipfilesystem'
require 'rchardet19'

configure do
  set :public_folder      , Proc.new { File.join(root, 'static') }
  set :subtitle_folder    , Proc.new { File.join(root, 'static', 'subtitle') }
  set :cache_folder       , Proc.new { File.join(root, 'static', 'cache') }
  set :video_ext_types    , %w{.mkv .rmvb .mp4}
  set :subtitle_ext_types , %w{.srt}
  set :job                , OpenStruct.new(:video => '', :video_name => '', :subtitle => '', :audio_stream=>'1')
  set :vtt                , Proc.new { File.join(root, 'static', 'cache', 'subtitle.vtt') }
  set :ffmpeg_path        , '/usr/local/bin/ffmpeg'
  set :cookie             , Proc.new { File.join(File.expand_path('~'), '.xunlei.lixian.cookies') }
  set :gdriveid           , File.new(settings.cookie, 'r').each_line.find{|line| line =~ /gdriveid/}.split(';').first.split('=').last
end

class String
  def enc
     CharDet.detect(self[0..512]).encoding
  end
  def yyets_srt
    self.encode!('UTF-8', self.enc) =~ /繁体\&英文\.srt$/ ? self.split('/').last : nil
  end 
end

helpers do
  
  def media_uri
    uri = settings.job.subtitle.empty? ? 'cache/movie.m3u8' : 'cache/play.m3u8'
  end

  def partial (template, locals = {})
    erb(template, :layout => false, :locals => locals)
  end
  
  def get_xunlei_file(file_name = nil)
    cmd = "lx list mkv mp4 --dcid -gcid --download-url"
    cmd += " | grep \"#{file_name}\"" if  file_name
    stdout_str       = `#{cmd}` 
    keys             = %w{no name status dcid gcid url}
    xunlei_file_list = stdout_str.force_encoding('utf-8').each_line.map{ |line| Hash[keys.zip(line.split(' '))] }.select{ |file| file['status'] == 'completed' && file['url'] =~ /^http/ }
  end

  def prepare_subtitle
    webvtt_lines = []
    webvtt_lines << %{WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:900000. LOCAL:00:00:00.000}
    
    unless settings.job.subtitle.empty?
      subtitle_file       = File.new(settings.job.subtitle, 'r').read
      subtitle_encodeing  =  subtitle_file.enc
      subtitle_file.encode!('UTF-8', subtitle_encodeing, :invalid => :replace, :undef => :replace, :replace => "?") unless subtitle_encodeing =~ /utf-8/i
      SRT::File.parse(subtitle_file).lines.delete_if{ |line| line.start_time.nil? }.sort_by{ |line| line.start_time }.uniq{ |line| line.start_time }.each{ |line|  webvtt_lines << "#{srt_line_to_webvtt(line)}" } 
    else
      webvtt_lines << "00:00:02.090 --> 02:00:00.000 vertical:lr align:end\n -"
    end
    
    file=File.new(settings.vtt, 'w')
    file.write(webvtt_lines.compact.join("\n\n"))
    file.close 
  end

  def srt_line_to_webvtt(line)
    text = line.text.join("\n").gsub(/^{.*}/, '').gsub(/<\/?[^>]*>/, '')
    
    if text.scan(/\d\d\d/).size >= 5
      return nil
    else
      time_srt = line.time_str.gsub(',', '.')
      return [time_srt,text].join("\n")
    end
  end
  
  def get_subtitle(gcid,dcid,match=true)
    xunlei_url  = "http://i.vod.xunlei.com/subtitle/list?gcid=#{gcid}&cid=#{dcid}&userid=153322167"
    
    subtitles   = JSON.parse(open(xunlei_url).read)['sublist']
    
    begin
      if match
        subtitle  = subtitles.select{ |sub| sub['sname'] =~ /srt$/i && sub['sname'] =~ /[\u4e00-\u9fa5]|ch/i}[0]
        filename  = params[:name].sub(/(#{settings.video_ext_types.join('|')})$/i,'.srt')
        File.new(settings.subtitle_folder + '/' + filename,'wb').write(open(subtitle['surl']).read) if subtitle['surl']
        return filename
      else
        subtitles
      end
    rescue Exception => e
      logger.info "subtitle not find!"
      return nil
    end
    
  end

  def gen_m3u8
    if settings.job.video
      
      cmd_step_1    = "cd #{settings.cache_folder}"
      cmd_step_2    = "printf -v cookie 'Cookie: gdriveid=#{settings.gdriveid}\\r\\n'"
      ffmpeg_video  = "-vcodec copy -vbsf h264_mp4toannexb -flags +global_header -map 0:v:0"
      ffmpeg_arvg   = "-map 0:a:#{settings.job.audio_stream} -async 1 -threads 0 -f segment -segment_time 5 -segment_list movie.m3u8 -segment_format mpegts -segment_list_flags live -force_key_frames 'expr:gte(t,n_forced*3)' stream%05d.ts"
      
      case RUBY_PLATFORM
      when  /mips/
        cmd_step_3  = "wget --header 'Cookie: gdriveid=#{settings.gdriveid};' '#{Base64.decode64(settings.job.video)}' -O - 2>/dev/null | #{settings.ffmpeg_path} -i pipe:0 #{ffmpeg_video} -acodec copy #{ffmpeg_arvg}"
      when /darwin/
        cmd_step_3  = "#{settings.ffmpeg_path} -headers \"$cookie\" -i '#{Base64.decode64(settings.job.video)}' #{ffmpeg_video} -acodec aac -strict experimental -ac 2 -ab 160k -ar 48000 #{ffmpeg_arvg}"  
      end

      movie_cmd     = cmd_step_1 + ';' + cmd_step_2 + ';' + cmd_step_3
      
      logger.info "-"*80
      logger.info movie_cmd
      logger.info "-"*80
      
      begin
        system('killall ffmpeg')
        system("cd #{settings.cache_folder};rm -rf *.ts")
      rescue Exception => e
        logger.info e
      end
      
      Process.spawn(movie_cmd)
      sleep 10
    end
  end
  
  def get_yyets_sub(id,filename)
    tmpdir  = Dir.mktmpdir
    sub_id  = id =~ /^\d+/ ? id : id.split('/').last
    cmd     = "cd #{tmpdir};wget \"http://www.yyets.com/subtitle/index/download?id=#{sub_id}\" -O temp.rar;unrar x temp"
    system(cmd)
    file    = Find.find(tmpdir).select{ |path| path =~ /繁体\&英文\.srt$/}
    sub_file  = settings.subtitle_folder + '/' + filename
    system("rm -rf \"#{sub_file}\"")
    system("mv \"#{file[0]}\" \"#{sub_file}\"")
    system("rm -rf #{tmpdir}")
    # zip_file  = open("http://www.yyets.com/subtitle/index/download?id=#{sub_id}")
    # sub_file  = settings.subtitle_folder + '/' + filename
    # file=Zip::ZipFile.open(zip_file).find{|file|  file.name.yyets_srt}
    # system("rm -rf \"#{sub_file}\"")
    # file.extract(sub_file)
  end
  
  def job_reset
    settings.job.video = settings.job.video_name = settings.job.subtitle = ''
    settings.job.audio_stream = 0
  end
  
end

before %r{.+\.json$} do
  content_type 'application/json'
end

before /add_to_job/ do

  if params[:type] == 'video'
    
    job_reset
    exist_file = File.join(settings.subtitle_folder, params[:name].sub(/(#{settings.video_ext_types.join('|')})$/i,'.srt'))
    
    if File.exists?(exist_file)
      params.merge!(:subtitle => exist_file)
    # else
    #   xunlei_file = get_xunlei_file(params[:name])[0]
    #   subtitle    = get_subtitle(xunlei_file['gcid'],xunlei_file['dcid'])
    #   subtitle    ? params.merge!(:subtitle => File.join(settings.subtitle_folder, subtitle)) : nil
    end
  
  end

end

get '/' do
  erb ''
end

get '/play' do
  sub=prepare_subtitle
  gen_m3u8
  erb :play
end

get '/get_xunlei_subtitle' do
  xunlei_file = get_xunlei_file(params[:name])[0]
  @subtitles = get_subtitle(xunlei_file['gcid'],xunlei_file['dcid'],false)
  # logger.info @subtitles
  erb :xunlei_subtitle,:layout => false
end

get '/download_sub' do
  begin
    File.new(settings.subtitle_folder + '/' + params[:name],'wb').write(open(params[:url]).read)
    settings.job.subtitle = settings.subtitle_folder + '/' + params[:name]
    "#{params[:name]} has been added"
  rescue Exception => e
    "#{params[:name]} has been failed"
  end
end

get '/preview_sub' do
  open(params[:url]).read
end

get '/xunlei' do
  @xunlei_files = get_xunlei_file
  
  erb :xunlei
end 

get '/subtitle' do
  @subtitle_files = Find.find(settings.subtitle_folder).select{ |path| path =~ /(#{settings.subtitle_ext_types.join('|')})$/i}
  erb :subtitle
end

get '/delete_job_subtitle' do
  @job = settings.job
  @job.subtitle   = settings.job.subtitle   = ''
  ''
end

get '/job' do
  @job = settings.job
  
  erb :job
end

get '/clean_job' do
  job_reset
  redirect  '/job' 
end

get '/add_to_job' do
  @job = settings.job
  @job.audio_stream = settings.job.audio_stream  = 0
  
  case params[:type]
  when 'video'
    @job.video      = settings.job.video      = params[:file]
    @job.video_name = settings.job.video_name = params[:name]
    @job.subtitle   = settings.job.subtitle   = params[:subtitle] if params[:subtitle]
  when 'subtitle'
    @job.subtitle   = settings.job.subtitle   = params[:file]
  end
  
  erb :job 
end

get '/task' do
  erb :task
end

post '/task' do
  system("lx add #{params[:url]}")
  redirect '/xunlei'
end

get '/audio_stream' do
  settings.job.audio_stream = 1
  "audio_stream 2"
end

get '/yyets_sub' do
  begin
    get_yyets_sub(params[:id],params[:name])
    'YYets subtile has been added'
  rescue Exception => e
    logger.info e
    'YYets subtile has been failed!'
  end
  

end

get '/kill_ffmpeg' do
  system("killall ffmpeg")
  "FFmpeg has been killed!"
end
