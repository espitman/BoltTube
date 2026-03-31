package ir.boum.bolttube.tv

import android.content.Intent
import android.graphics.drawable.GradientDrawable
import android.media.MediaMetadataRetriever
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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
                    .putExtra(VideoPlayerActivity.EXTRA_STREAM_URL, item.streamUrl)
                    .putExtra(VideoPlayerActivity.EXTRA_TITLE, item.title),
            )
        }

        libraryGrid = view.findViewById<RecyclerView>(R.id.libraryGrid).apply {
            layoutManager = GridLayoutManager(requireContext(), 3)
            adapter = this@TvBrowseFragment.adapter
            itemAnimator = null
            if (itemDecorationCount == 0) {
                addItemDecoration(ExactGridSpacingDecoration(spanCount = 3, spacingPx = dp(10)))
            }
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
                        VideoItem(
                            id = item.id,
                            title = item.fileName.removeSuffix(".mp4"),
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

    private fun dp(value: Int): Int {
        return (value * requireContext().resources.displayMetrics.density).toInt()
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
                    .scaleX(if (hasFocus) 1.03f else 1f)
                    .scaleY(if (hasFocus) 1.03f else 1f)
                    .setDuration(140)
                    .start()
                view.alpha = if (hasFocus) 1f else 0.98f
                titleView.isSelected = hasFocus
            }
        }

        fun bind(item: VideoItem) {
            boundItem = item
            titleView.text = item.title
            titleView.isSelected = itemView.isFocused
            subtitleView.text = durationCache[item.id] ?: "..."

            Glide.with(itemView)
                .load(item.thumbnailUrl)
                .fitCenter()
                .placeholder(placeholder(itemView))
                .error(placeholder(itemView))
                .into(imageView)

            loadDuration(item)
        }

        private fun loadDuration(item: VideoItem) {
            durationCache[item.id]?.let { cached ->
                subtitleView.text = cached
                return
            }

            val expectedId = item.id
            executor.execute {
                val duration = runCatching {
                    MediaMetadataRetriever().use { retriever ->
                        retriever.setDataSource(item.streamUrl, emptyMap())
                        val millis = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                            ?.toLongOrNull()
                            ?: 0L
                        formatDuration(millis)
                    }
                }.getOrElse { "--:--" }

                durationCache[expectedId] = duration
                mainHandler.post {
                    if (boundItem?.id == expectedId) {
                        subtitleView.text = duration
                    }
                }
            }
        }

        private fun placeholder(view: View) = GradientDrawable().apply {
            cornerRadius = dp(view, 18).toFloat()
            setColor(ContextCompat.getColor(view.context, R.color.tv_surface_alt))
        }
    }
}

private class ExactGridSpacingDecoration(
    private val spanCount: Int,
    private val spacingPx: Int,
) : RecyclerView.ItemDecoration() {
    override fun getItemOffsets(
        outRect: android.graphics.Rect,
        view: View,
        parent: RecyclerView,
        state: RecyclerView.State,
    ) {
        val position = parent.getChildAdapterPosition(view)
        if (position == RecyclerView.NO_POSITION) return

        val column = position % spanCount
        outRect.left = 0
        outRect.right = if (column == spanCount - 1) 0 else spacingPx
        outRect.top = if (position < spanCount) 0 else spacingPx
        outRect.bottom = 0
    }
}

private fun dp(view: View, value: Int): Int {
    return (value * view.resources.displayMetrics.density).toInt()
}

private fun formatDuration(durationMs: Long): String {
    val totalSeconds = (durationMs / 1000).coerceAtLeast(0)
    val hours = totalSeconds / 3600
    val minutes = (totalSeconds % 3600) / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) {
        String.format("%d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format("%02d:%02d", minutes, seconds)
    }
}
