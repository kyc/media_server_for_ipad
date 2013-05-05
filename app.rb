require 'rubygems'
require 'sinatra'
require 'open-uri'
require 'open3'
require 'json'
require 'find'
require 'ostruct'
require 'srt'
require "base64"

configure do
  set :public_folder, Proc.new { File.join(root, "static") }
  set :subtitle_folder, Proc.new { File.join(root, "static", "subtitle") }
  set :cache_folder, Proc.new { File.join(root, "static", "cache") }
  set :video_ext_types, %w{.mkv .rmvb .mp4}
  set :subtitle_ext_types, %w{.srt}
  set :job, OpenStruct.new(:video => '',:subtitle => '')
  set :vtt, Proc.new { File.join(root, "static", "cache","subtitle.vtt") }
  set :ffmpeg_path, '/usr/local/bin/ffmpeg'
  set :cookie, '/Users/kyc/.xunlei.lixian.cookies'
  set :gdriveid, File.new(settings.cookie,'r').each_line.find{|line| line =~ /gdriveid/}.split(';').first.split('=').last
end

helpers do

  def partial (template, locals = {})
    erb(template, :layout => false, :locals => locals)
  end
end

before %r{.+\.json$} do
  content_type 'application/json'
end



get '/' do
  erb 'Can you handle a <a href="/secure/place">secret</a>?'
end

def get_xunlei_file
  stdout_str, status = Open3.capture2("lx list mkv mp4 --dcid -gcid --download-url")  
  keys=%w{no name status dcid gcid url}
  xunlei_file_list=stdout_str.force_encoding('utf-8').each_line.map{|line| Hash[keys.zip(line.split(' '))] }.delete_if{|file| file['status'] != 'completed'}
end

def prepare_subtitle
  webvtt_lines  = []
  webvtt_lines  << %{WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:900000. LOCAL:00:00:00.000}
  unless settings.job.subtitle.empty?
    subtitle_file = File.new(settings.job.subtitle, "r").read
    SRT::File.parse(subtitle_file).lines.sort_by{ |line| line.start_time}.uniq{|line| line.start_time}.each do |line|
      webvtt_lines  <<  "#{srt_line_to_webvtt(line)}"
    end
  else
    webvtt_lines << "00:00:02.090 --> 03:00:00.000"
  end 
  File.new(settings.vtt, "w").write(webvtt_lines.compact.join("\n\n"))
end

def srt_line_to_webvtt(line)
  text  = line.text.join("\n").gsub(/^{.*}/,'').gsub(/<\/?[^>]*>/, "")
  if text.scan(/\d\d\d/).size >= 5
    return nil
  else
    time_srt  = line.time_str.gsub(',','.')
    return [time_srt,text].join("\n")
  end
end

def gen_m3u8
  if settings.job.video
    cmd_step_1 = "cd #{settings.cache_folder}"
    cmd_step_2 = "printf -v cookie 'Cookie: gdriveid=#{settings.gdriveid}\\r\\n'"
    logger.info Base64.decode64(settings.job.video)
    cmd_step_3 = "#{settings.ffmpeg_path} -headers \"$cookie\" -i \"#{Base64.decode64(settings.job.video)}\" -vcodec copy -acodec aac -strict -2 -vbsf h264_mp4toannexb -map 0 -f segment -segment_time 4 -segment_list_size 0 -segment_list movie.m3u8 -segment_format mpegts stream%05d.ts > ffmpeg.log"
    movie_cmd = cmd_step_1 + ';' + cmd_step_2 + ';' + cmd_step_3
    # uid = Process.uid
    begin
      system('killall ffmpeg')
      system("cd #{settings.cache_folder};rm -rf *.ts")
    rescue Exception => e
      
    end
    Process.spawn(movie_cmd)
  end
end

get '/play' do
  sub=prepare_subtitle
  gen_m3u8
  erb :play
end

get '/get_xunlei_subtitle' do  
  xunlei_url="http://i.vod.xunlei.com/subtitle/list?gcid=#{params[:gcid]}&cid=#{params[:dcid]}&userid=153322167"
  subtitles=JSON.parse(open(xunlei_url).read)['sublist']
  begin
    subtitle=subtitles.find{|sub| sub['sname'] =~ /srt$/i}
    filename = params[:name].sub(/(#{settings.video_ext_types.join('|')})$/i,'.srt')
    File.new(settings.subtitle_folder + '/' + filename,'wb').write(open(subtitle['surl']).read)
  rescue Exception => e
    logger.info e
  end
  redirect '/subtitle'
end

get '/xunlei' do
  @xunlei_files = get_xunlei_file
  erb :xunlei
end 

get '/subtitle' do
  logger.info settings.video_ext_types
  @subtitle_files = Find.find(settings.subtitle_folder).select{ |path| path =~ /(#{settings.subtitle_ext_types.join('|')})$/i}
  erb :subtitle
end

get '/job' do
  @job = settings.job
  erb :job
end

get '/clean_job' do
  settings.job=OpenStruct.new(:video => '',:subtitle => '')
  redirect '/job' 
end

get '/add_to_job' do
  @job = settings.job
  case params[:type]
  when 'video'
    @job.video = settings.job.video = params[:file]
  when 'subtitle'
    @job.subtitle = settings.job.subtitle =params[:file]
  end  
  erb :job 
end