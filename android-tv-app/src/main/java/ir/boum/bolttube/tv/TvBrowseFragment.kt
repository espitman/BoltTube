package ir.boum.bolttube.tv

import android.content.Intent
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.widget.NestedScrollView
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class TvBrowseFragment : Fragment() {

    val viewModel: TvViewModel by activityViewModels()

    private lateinit var libraryContent: View
    private lateinit var channelDetailContent: View
    private lateinit var libraryGrid: RecyclerView
    private lateinit var channelScrollView: NestedScrollView
    private lateinit var channelSectionsContainer: LinearLayout
    private lateinit var emptyView: TextView
    private lateinit var channelEmptyView: TextView
    private lateinit var channelLoading: View
    private lateinit var channelTitle: TextView
    private lateinit var channelHeroImage: ImageView
    private lateinit var channelBackButton: View
    private lateinit var libraryAdapter: TvVideoCardAdapter

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        return inflater.inflate(R.layout.fragment_tv_browse, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        libraryAdapter = TvVideoCardAdapter(::openVideo)
        libraryContent = view.findViewById(R.id.libraryContent)
        channelDetailContent = view.findViewById(R.id.channelDetailContent)
        emptyView = view.findViewById(R.id.emptyView)
        channelEmptyView = view.findViewById(R.id.channelEmptyView)
        channelLoading = view.findViewById(R.id.channelLoading)
        channelTitle = view.findViewById(R.id.channelTitle)
        channelHeroImage = view.findViewById(R.id.channelHeroImage)
        channelBackButton = view.findViewById(R.id.channelBackButton)

        libraryGrid = view.findViewById<RecyclerView>(R.id.libraryGrid).apply {
            layoutManager = GridLayoutManager(requireContext(), 3)
            adapter = libraryAdapter
            itemAnimator = null
        }

        channelScrollView = view.findViewById(R.id.channelScrollView)
        channelSectionsContainer = view.findViewById(R.id.channelSectionsContainer)

        channelBackButton.setOnClickListener {
            viewModel.clearSelectedChannel()
        }
        channelBackButton.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) {
                channelScrollView.smoothScrollTo(0, 0)
            }
        }

        observeViewModel()
    }

    fun openServerDialog() {
        ServerConfigDialogFragment.newInstance(viewModel.uiState.value.serverUrl)
            .show(parentFragmentManager, "server_config")
    }

    fun submitServerUrl(url: String) {
        viewModel.saveServerUrl(url)
    }

    private fun openVideo(item: VideoItem) {
        startActivity(
            Intent(requireContext(), VideoPlayerActivity::class.java)
                .putExtra(VideoPlayerActivity.EXTRA_STREAM_URL, item.streamUrl)
                .putExtra(VideoPlayerActivity.EXTRA_TITLE, item.title),
        )
    }

    private fun ensureSectionVisible(sectionView: View, focusedCardView: View) {
        val sectionTop = IntArray(2).also { sectionView.getLocationInWindow(it) }[1]
        val scrollTop = IntArray(2).also { channelScrollView.getLocationInWindow(it) }[1]
        
        val relativeTop = sectionTop - scrollTop
        val topSafe = dpToPx(12)
        
        if (relativeTop < topSafe) {
            channelScrollView.smoothScrollBy(0, relativeTop - topSafe)
        } else {
            val cardBottom = IntArray(2).also { focusedCardView.getLocationInWindow(it) }[1] + focusedCardView.height
            val scrollBottom = scrollTop + channelScrollView.height
            val bottomSafe = dpToPx(48)
            
            if (cardBottom > scrollBottom - bottomSafe) {
                val dy = cardBottom - (scrollBottom - bottomSafe)
                val canScrollDown = relativeTop - topSafe
                channelScrollView.smoothScrollBy(0, minOf(dy, canScrollDown))
            }
        }
    }

    private fun dpToPx(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics,
        ).toInt()
    }

    private fun observeViewModel() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiState.collect { state ->
                    val libraryItems = state.library.map(::mediaToVideoItem)
                    libraryAdapter.submit(libraryItems)
                    emptyView.visibility = if (libraryItems.isEmpty() && state.selectedChannel == null) View.VISIBLE else View.GONE

                    if (state.selectedChannel == null) {
                        libraryContent.visibility = View.VISIBLE
                        channelDetailContent.visibility = View.GONE
                    } else {
                        libraryContent.visibility = View.GONE
                        channelDetailContent.visibility = View.VISIBLE

                        channelTitle.text = state.selectedChannel.name
                        if (state.selectedChannel.thumbnailUrl.isNullOrBlank()) {
                            channelHeroImage.setImageDrawable(null)
                        } else {
                            Glide.with(channelHeroImage)
                                .load(viewModel.absoluteMediaUrl(state.selectedChannel.thumbnailUrl))
                                .centerCrop()
                                .into(channelHeroImage)
                        }

                        channelLoading.visibility = if (state.channelContentLoading) View.VISIBLE else View.GONE
                        val sectionModels = state.channelContent.map { section ->
                            TvChannelSectionModel(
                                title = section.playlist.name,
                                items = section.items.map(::mediaToVideoItem),
                            )
                        }
                        renderChannelSections(sectionModels)
                        if (!state.channelContentLoading && sectionModels.isNotEmpty()) {
                            channelScrollView.post { 
                                channelScrollView.scrollTo(0, 0)
                                // Auto-focus first item of first section
                                val firstSection = channelSectionsContainer.getChildAt(0)
                                val itemsView = firstSection?.findViewById<RecyclerView>(R.id.sectionItems)
                                itemsView?.post {
                                    itemsView.getChildAt(0)?.requestFocus()
                                }
                            }
                        }
                        channelEmptyView.text = if (state.channelContentLoading) "" else getString(R.string.empty_channel)
                        channelEmptyView.visibility = if (!state.channelContentLoading && sectionModels.isEmpty()) View.VISIBLE else View.GONE
                    }
                }
            }
        }
    }

    private fun mediaToVideoItem(item: MediaSummary): VideoItem {
        val displayTitle = item.title.ifBlank {
            item.fileName.removeSuffix(".mp4")
                .replaceFirst(Regex("^\\d+[\\s._\\-]*"), "")
                .replace("_", " ")
                .trim()
        }
        return VideoItem(
            id = item.id,
            title = displayTitle,
            subtitle = "",
            thumbnailUrl = item.thumbnailUrl?.let(viewModel::absoluteMediaUrl),
            streamUrl = viewModel.absoluteMediaUrl(item.streamUrl),
        )
    }

    private fun renderChannelSections(sections: List<TvChannelSectionModel>) {
        channelSectionsContainer.removeAllViews()
        sections.forEachIndexed { index, section ->
            val sectionView = layoutInflater.inflate(
                R.layout.item_channel_section,
                channelSectionsContainer,
                false,
            )
            val titleView = sectionView.findViewById<TextView>(R.id.sectionTitle)
            val itemsView = sectionView.findViewById<RecyclerView>(R.id.sectionItems)
            val adapter = TvVideoCardAdapter(
                onClick = ::openVideo,
                onFocusGained = { focusedCard -> ensureSectionVisible(sectionView, focusedCard) },
                horizontalCardWidthPx = homeCardWidthPx(),
                nextFocusUpId = if (index == 0) R.id.channelBackButton else View.NO_ID,
            )

            titleView.text = section.title
            itemsView.layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false)
            itemsView.adapter = adapter
            adapter.submit(section.items)

            channelSectionsContainer.addView(sectionView)
        }
    }

    private fun homeCardWidthPx(): Int {
        val contentWidth = libraryGrid.width - libraryGrid.paddingStart - libraryGrid.paddingEnd
        return if (contentWidth > 0) contentWidth / 3 else dpToPx(320)
    }
}

private data class TvChannelSectionModel(
    val title: String,
    val items: List<VideoItem>,
)

private class TvVideoCardAdapter(
    private val onClick: (VideoItem) -> Unit,
    private val onFocusGained: ((View) -> Unit)? = null,
    private val horizontalCardWidthPx: Int? = null,
    private val nextFocusUpId: Int = View.NO_ID,
) : RecyclerView.Adapter<TvVideoCardAdapter.VideoViewHolder>() {

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
        val layoutManager = (parent as? RecyclerView)?.layoutManager
        if (layoutManager is LinearLayoutManager && layoutManager.orientation == LinearLayoutManager.HORIZONTAL && horizontalCardWidthPx != null) {
            view.layoutParams = RecyclerView.LayoutParams(
                horizontalCardWidthPx,
                RecyclerView.LayoutParams.WRAP_CONTENT,
            )
        }
        if (nextFocusUpId != View.NO_ID) {
            view.nextFocusUpId = nextFocusUpId
        }
        return VideoViewHolder(view, onClick, onFocusGained)
    }

    override fun onBindViewHolder(holder: VideoViewHolder, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    class VideoViewHolder(
        itemView: View,
        private val onClick: (VideoItem) -> Unit,
        private val onFocusGained: ((View) -> Unit)?,
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
                titleView.isSelected = hasFocus
                if (hasFocus) {
                    onFocusGained?.invoke(view)
                }
            }
        }

        fun bind(item: VideoItem) {
            boundItem = item
            titleView.text = item.title
            titleView.isSelected = itemView.isFocused
            subtitleView.text = durationCache[item.id] ?: ""

            if (isPersian(item.title)) {
                try {
                    val vazir = androidx.core.content.res.ResourcesCompat.getFont(itemView.context, R.font.vazir)
                    titleView.typeface = vazir
                } catch (_: Exception) {
                    titleView.setTypeface(null, android.graphics.Typeface.BOLD)
                }
            } else {
                titleView.setTypeface(null, android.graphics.Typeface.BOLD)
            }

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
