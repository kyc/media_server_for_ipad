
 $(function() {
    $("button#video_reload").click(function(){
			var div			= $("#video");
			var content	=	div.html();
			div.empty().append(content);
    });
});
