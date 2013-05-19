
$(function() {
    $("button#video_reload").click(function(){
			var div			= $("#video");
			var content	=	div.html();
			div.empty().append(content);
    });
});

$(function() {
    $("button#audio_stream").click(function(){
			console.log('audio_stream')
			// $("button#change_steam").html(ajax_load);  
			        $.get(  
			            '/audio_stream',  
			            function(responseText){  
			                $("button#audio_stream").html(responseText);  
			            },  
			            "html"  
			        );  
    });
});

 $(function() {
	 $("button#get_yyets_sub").click(function(){
		 // var yyets_id		=$("input#yyets_sub_id").val().split('/').pop();
		 var yyets_id		=$("input#yyets_sub_id").val()
		 var yyets_name	=$("td#video_name").text().replace('mkv','srt').trim();
			 $.get("yyets_sub", { id: yyets_id, name: yyets_name})
				 .done(function(responseText) {
				   $("button#get_yyets_sub").html(responseText);  
				 });
			 });
});