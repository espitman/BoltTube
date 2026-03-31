package ir.boum.bolttube.tv

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class TvBrowseFragment : Fragment() {

    val viewModel: TvViewModel by activityViewModels()

    private lateinit var libraryGrid: RecyclerView
    private lateinit var emptyView: TextView
    private lateinit var adapter: TvLibraryAdapter

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        return inflater.inflate(R.layout.fragment_tv_browse, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        adapter = TvLibraryAdapter { item ->
            startActivity(
                Intent(requireContext(), VideoPlayerActivity::class.java)
                    .putExtra("VIDEO_URL", item.streamUrl)
                    .putExtra("VIDEO_TITLE", item.title),
            )
        }

        libraryGrid = view.findViewById<RecyclerView>(R.id.libraryGrid).apply {
            layoutManager = GridLayoutManager(requireContext(), 3)
            adapter = this@TvBrowseFragment.adapter
            itemAnimator = null
        }

        emptyView = view.findViewById(R.id.emptyView)

        observeViewModel()
    }

    fun openServerDialog() {
        ServerConfigDialogFragment.newInstance(viewModel.uiState.value.serverUrl)
            .show(parentFragmentManager, "server_config")
    }

    fun submitServerUrl(url: String) {
        viewModel.saveServerUrl(url)
    }

    private fun observeViewModel() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiState.collect { state ->
                    val items = state.library.map { item ->
                        val rawName = item.fileName.removeSuffix(".mp4")
                        // Smart Clean: Remove leading numbers (1_ ...) and replace underscores
                        val cleanTitle = rawName.replaceFirst(Regex("^\\d+_"), "")
                            .replace("_", " ")
                            .trim()

                        VideoItem(
                            id = item.id,
                            title = cleanTitle,
                            subtitle = "",
                            thumbnailUrl = item.thumbnailUrl,
                            streamUrl = viewModel.absoluteMediaUrl(item.streamUrl),
                        )
                    }
                    adapter.submit(items)
                    emptyView.visibility = if (items.isEmpty()) View.VISIBLE else View.GONE
                }
            }
        }
    }
}

private class TvLibraryAdapter(
    private val onClick: (VideoItem) -> Unit,
) : RecyclerView.Adapter<TvLibraryAdapter.VideoViewHolder>() {

    companion object {
        private val durationCache = ConcurrentHashMap<String, String>()
        private val executor = Executors.newFixedThreadPool(2)
        private val mainHandler = Handler(Looper.getMainLooper())
    }

    private val items = mutableListOf<VideoItem>()

    fun submit(newItems: List<VideoItem>) {
        items.clear()
        items.addAll(newItems)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VideoViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_tv_video_card, parent, false)
        return VideoViewHolder(view, onClick)
    }

    override fun onBindViewHolder(holder: VideoViewHolder, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    class VideoViewHolder(
        itemView: View,
        private val onClick: (VideoItem) -> Unit,
    ) : RecyclerView.ViewHolder(itemView) {
        private val imageView = itemView.findViewById<ImageView>(R.id.cardImage)
        private val titleView = itemView.findViewById<TextView>(R.id.cardTitle)
        private val subtitleView = itemView.findViewById<TextView>(R.id.cardSubtitle)
        private var boundItem: VideoItem? = null

        init {
            itemView.setOnClickListener {
                boundItem?.let(onClick)
            }
            itemView.setOnFocusChangeListener { view, hasFocus ->
                view.animate()
                    .scaleX(if (hasFocus) 1.05f else 1f)
                    .scaleY(if (hasFocus) 1.05f else 1f)
                    .translationZ(if (hasFocus) 16f else 0f)
                    .setDuration(160)
                    .start()
                titleView.alpha = if (hasFocus) 1f else 0.85f
                titleView.isSelected = hasFocus // Trigger Translucent Marquee
            }
        }

        fun bind(item: VideoItem) {
            boundItem = item
            titleView.text = item.title
            titleView.isSelected = itemView.isFocused
            subtitleView.text = durationCache[item.id] ?: ""

            // Apply Vazir font if Persian text is detected
            if (isPersian(item.title)) {
                try {
                    val fontId = itemView.context.resources.getIdentifier("vazir", "font", itemView.context.packageName)
                    if (fontId != 0) {
                        val vazir = androidx.core.content.res.ResourcesCompat.getFont(itemView.context, fontId)
                        titleView.typeface = vazir
                    } else {
                        titleView.setTypeface(null, android.graphics.Typeface.BOLD)
                    }
                } catch (e: Exception) {
                    titleView.setTypeface(null, android.graphics.Typeface.BOLD)
                }
            } else {
                titleView.setTypeface(null, android.graphics.Typeface.BOLD)
            }

            Log.d("TvLibraryAdapter", "Loading thumb for ${item.title}: ${item.thumbnailUrl}")
            Glide.with(itemView)
                .load(item.thumbnailUrl)
                .centerCrop()
                .placeholder(android.R.color.transparent)
                .error(android.R.color.transparent)
                .into(imageView)

            loadDuration(item)
        }

        private fun isPersian(text: String): Boolean {
            for (char in text) {
                if (char in '\u0600'..'\u06FF') return true
            }
            return false
        }

        private fun loadDuration(item: VideoItem) {
            durationCache[item.id]?.let { cached ->
                subtitleView.text = cached
                return
            }

            val expectedId = item.id
            executor.execute {
                val duration = runCatching {
                    android.media.MediaMetadataRetriever().use { retriever ->
                        retriever.setDataSource(item.streamUrl, emptyMap())
                        val millis = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                            ?.toLongOrNull()
                            ?: 0L
                        formatDuration(millis)
                    }
                }.getOrElse { "" }

                durationCache[expectedId] = duration
                mainHandler.post {
                    if (boundItem?.id == expectedId) {
                        subtitleView.text = duration
                    }
                }
            }
        }

        private fun formatDuration(durationMs: Long): String {
            val totalSeconds = (durationMs / 1000).coerceAtLeast(0)
            val hours = totalSeconds / 3600
            val minutes = (totalSeconds % 3600) / 60
            val seconds = totalSeconds % 60
            return if (hours > 0) String.format("%d:%02d:%02d", hours, minutes, seconds)
            else String.format("%02d:%02d", minutes, seconds)
        }
    }
}
