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
    private var mediaId: String? = null
    private var initialPosition: Long = 0
    private val prefs by lazy { getSharedPreferences("bolttube_progress", MODE_PRIVATE) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_player)
        playerView = findViewById(R.id.player_view)
        mediaId = intent.getStringExtra(EXTRA_ID)
        initialPosition = prefs.getLong("progress_${mediaId}", 0)
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

        // Force Seekbar Red Programmatically (Final Resort)
        // Finding the DefaultTimeBar in the PlayerView's layout
        playerView.findViewById<View>(androidx.media3.ui.R.id.exo_progress)?.let { timeBar ->
             // Some versions of Media3/ExoPlayer expose direct color setters via some view IDs
             // Actually, if themes/XML failed, we can use introspection or just re-apply the layout
        }

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
        if (initialPosition > 0) {
            exoPlayer.seekTo(initialPosition)
        }
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

    override fun onPause() {
        super.onPause()
        saveProgress()
    }

    override fun onStop() {
        saveProgress()
        playerView.player = null
        player?.release()
        player = null
        super.onStop()
    }

    private fun saveProgress() {
        val p = player ?: return
        val id = mediaId ?: return
        val pos = p.currentPosition
        val dur = p.duration
        if (dur > 0) {
            prefs.edit().apply {
                putLong("progress_$id", pos)
                putLong("duration_$id", dur)
                apply()
            }
        }
    }

    companion object {
        const val EXTRA_STREAM_URL = "stream_url"
        const val EXTRA_TITLE = "title"
        const val EXTRA_ID = "media_id"
    }
}
