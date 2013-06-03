bootstrap_alert = function() {}
bootstrap_alert.warning = function(message) {
            $('div#alert_placeholder').html('<div class="alert"><a class="close" data-dismiss="alert">×</a><span>'+message+'</span></div>')
}


$(function() {
    $("button#video_reload").click(function(){
			var div			= $("#video");
			var content	=	div.html();
			div.empty().append(content);
    });
		
    $("button#audio_stream").click(function(){
      $.get(  
          '/audio_stream',  
          function(responseText){  
              $("button#audio_stream").html(responseText);  
          },  
          "html"  
      );  
    });
		
 	 $("button#get-yyets-sub").click(function(){
 		 var yyets_id		=$("input#yyets_sub_id").val()
 		 var yyets_name	=$("td#video_name").text().replace('mkv','srt').trim();
 			 $.get("yyets_sub", { id: yyets_id, name: yyets_name})
 				 .done(function(responseText) {
					 bootstrap_alert.warning(responseText); 
 				 });
 		});	
		
	 $("a#ffmpeg-btn").click(function(){
			 $.get("kill_ffmpeg")
				 .done(function(responseText) {
				   bootstrap_alert.warning(responseText); 
				 });
		});
		
 	 $("button#delete_job_subtitle").click(function(){
 			 $.get("delete_job_subtitle")
 				 .done(function(responseText) {
 				   $("td#job_subtitle").html(responseText);  
 				 });
 		});
		
  	 $("button#get_job_subtitle").click(function(){
			 var movie_name	= $("td#video_name").text().trim();
  			 $.get("get_xunlei_subtitle", { name: movie_name})
  				 .done(function(responseText) {
						 $("div#subtitle_placeholder").html(responseText);
  				 });
  		});
			
});




