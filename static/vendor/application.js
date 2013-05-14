
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