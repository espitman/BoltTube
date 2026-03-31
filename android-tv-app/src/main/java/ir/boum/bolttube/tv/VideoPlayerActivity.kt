package ir.boum.bolttube.tv

import android.os.Bundle
import android.view.View
import android.view.Gravity
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView

class VideoPlayerActivity : AppCompatActivity() {

    private var player: ExoPlayer? = null
    private lateinit var playerView: PlayerView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_player)
        playerView = findViewById(R.id.player_view)
    }

    override fun onStart() {
        super.onStart()
        val streamUrl = intent.getStringExtra(EXTRA_STREAM_URL).orEmpty()
        val videoTitle = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        val titleView = findViewById<TextView>(R.id.player_video_title)

        if (streamUrl.isBlank()) {
            finish()
            return
        }

        // Setup Title UI
        titleView.text = videoTitle
        setupTitleAlignment(titleView, videoTitle)

        val exoPlayer = ExoPlayer.Builder(this).build()
        player = exoPlayer
        playerView.player = exoPlayer
        
        // Sync title visibility with controls
        playerView.setControllerVisibilityListener(PlayerView.ControllerVisibilityListener { visibility ->
            titleView.visibility = visibility
            if (visibility == View.VISIBLE) {
                titleView.isSelected = true // Start Marquee
            }
        })

        exoPlayer.setMediaItem(MediaItem.fromUri(streamUrl))
        exoPlayer.prepare()
        exoPlayer.playWhenReady = true
    }

    private fun setupTitleAlignment(view: TextView, text: String) {
        val isFa = text.any { it in '\u0600'..'\u06FF' }
        if (isFa) {
            view.textDirection = View.TEXT_DIRECTION_ANY_RTL
            view.gravity = Gravity.END
            try {
                val fontId = resources.getIdentifier("vazir", "font", packageName)
                if (fontId != 0) {
                    view.typeface = androidx.core.content.res.ResourcesCompat.getFont(this, fontId)
                } else {
                    view.setTypeface(null, android.graphics.Typeface.BOLD)
                }
            } catch (e: Exception) {
                view.setTypeface(null, android.graphics.Typeface.BOLD)
            }
        } else {
            view.textDirection = View.TEXT_DIRECTION_LTR
            view.gravity = Gravity.START
            view.setTypeface(null, android.graphics.Typeface.BOLD)
        }
    }

    override fun onStop() {
        playerView.player = null
        player?.release()
        player = null
        super.onStop()
    }

    companion object {
        const val EXTRA_STREAM_URL = "stream_url"
        const val EXTRA_TITLE = "title"
    }
}
