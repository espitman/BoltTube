package ir.boum.bolttube.tv

import android.content.Intent
import android.os.Bundle
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

class TvBrowseFragment : Fragment() {

    val viewModel: TvViewModel by activityViewModels()

    private lateinit var libraryContent: View
    private lateinit var channelDetailContent: View
    private lateinit var playlistDetailContent: View
    
    private lateinit var libraryGrid: RecyclerView
    private lateinit var channelScrollView: NestedScrollView
    private lateinit var channelSectionsContainer: LinearLayout
    private lateinit var playlistGrid: RecyclerView

    private lateinit var emptyView: TextView
    private lateinit var channelEmptyView: TextView
    private lateinit var channelLoading: View
    private lateinit var channelTitle: TextView
    private lateinit var channelHeroImage: ImageView
    private lateinit var channelBackButton: View

    private lateinit var playlistTitle: TextView
    private lateinit var playlistHeroImage: ImageView
    private lateinit var playlistBackButton: View

    private lateinit var libraryAdapter: TvVideoCardAdapter
    private lateinit var playlistAdapter: TvVideoCardAdapter

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        return inflater.inflate(R.layout.fragment_tv_browse, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        libraryAdapter = TvVideoCardAdapter(
            onClick = ::openVideo,
            onLongClick = ::openVideoActions,
        )
        playlistAdapter = TvVideoCardAdapter(
            onClick = ::openVideo,
            onLongClick = ::openVideoActions,
            nextFocusUpProvider = { pos -> if (pos < 3) R.id.playlistBackButton else View.NO_ID }
        )

        libraryContent = view.findViewById(R.id.libraryContent)
        channelDetailContent = view.findViewById(R.id.channelDetailContent)
        playlistDetailContent = view.findViewById(R.id.playlistDetailContent)
        
        emptyView = view.findViewById(R.id.emptyView)
        channelEmptyView = view.findViewById(R.id.channelEmptyView)
        channelLoading = view.findViewById(R.id.channelLoading)
        channelTitle = view.findViewById(R.id.channelTitle)
        channelHeroImage = view.findViewById(R.id.channelHeroImage)
        channelBackButton = view.findViewById(R.id.channelBackButton)

        playlistTitle = view.findViewById(R.id.playlistTitle)
        playlistHeroImage = view.findViewById(R.id.playlistHeroImage)
        playlistBackButton = view.findViewById<ImageView>(R.id.playlistBackButton).apply {
            nextFocusDownId = R.id.playlistGrid
        }

        libraryGrid = view.findViewById<RecyclerView>(R.id.libraryGrid).apply {
            layoutManager = GridLayoutManager(requireContext(), 3)
            adapter = libraryAdapter
            itemAnimator = null
        }

        playlistGrid = view.findViewById<RecyclerView>(R.id.playlistGrid).apply {
            layoutManager = GridLayoutManager(requireContext(), 3)
            adapter = playlistAdapter
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

        playlistBackButton.setOnClickListener {
            viewModel.clearSelectedPlaylist()
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
        if (item.isOffloaded) {
            OffloadedDownloadDialogFragment.newInstance(
                mediaId = item.id,
                title = item.title,
                thumbnailUrl = item.thumbnailUrl.orEmpty(),
            ).show(parentFragmentManager, "offloaded_download")
            return
        }
        startActivity(
            Intent(requireContext(), VideoPlayerActivity::class.java)
                .putExtra(VideoPlayerActivity.EXTRA_STREAM_URL, item.streamUrl)
                .putExtra(VideoPlayerActivity.EXTRA_TITLE, item.title)
                .putExtra(VideoPlayerActivity.EXTRA_ID, item.id),
        )
    }

    private fun openVideoActions(item: VideoItem) {
        TvVideoActionsDialogFragment.newInstance(
            mediaId = item.id,
            title = item.title,
            isOffloaded = item.isOffloaded,
        ).show(parentFragmentManager, "video_actions")
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

    override fun onResume() {
        super.onResume()
        libraryAdapter.notifyDataSetChanged()
    }

    private fun observeViewModel() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiState.collect { state ->
                    val libraryItems = state.library.sortedByDescending { it.createdAt }.map(::mediaToVideoItem)
                    libraryAdapter.submit(libraryItems)
                    emptyView.visibility = if (libraryItems.isEmpty() && state.selectedChannel == null && state.selectedPlaylist == null) View.VISIBLE else View.GONE

                    when {
                        state.selectedPlaylist != null -> {
                            libraryContent.visibility = View.GONE
                            channelDetailContent.visibility = View.GONE
                            playlistDetailContent.visibility = View.VISIBLE

                            playlistTitle.text = state.selectedPlaylist.name
                            if (state.selectedPlaylist.thumbnailUrl.isNullOrBlank()) {
                                playlistHeroImage.setImageDrawable(null)
                            } else {
                                Glide.with(playlistHeroImage)
                                    .load(viewModel.absoluteMediaUrl(state.selectedPlaylist.thumbnailUrl))
                                    .centerCrop()
                                    .into(playlistHeroImage)
                            }

                            val items = state.playlistContent.sortedByDescending { it.createdAt }.map(::mediaToVideoItem)
                            playlistAdapter.submit(items)
                            if (!state.playlistLoading && items.isNotEmpty()) {
                                playlistGrid.post {
                                    playlistGrid.getChildAt(0)?.requestFocus()
                                }
                            }
                        }
                        state.selectedChannel != null -> {
                            libraryContent.visibility = View.GONE
                            channelDetailContent.visibility = View.VISIBLE
                            playlistDetailContent.visibility = View.GONE

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
                                    items = section.items.sortedByDescending { it.createdAt }.take(10).map(::mediaToVideoItem),
                                    playlist = section.playlist,
                                )
                            }
                            renderChannelSections(sectionModels)
                            if (!state.channelContentLoading && sectionModels.isNotEmpty()) {
                                channelScrollView.post { 
                                    channelScrollView.scrollTo(0, 0)
                                    val firstSection = channelSectionsContainer.getChildAt(0)
                                    val itemsView = firstSection?.findViewById<RecyclerView>(R.id.sectionItems)
                                    if (itemsView != null && itemsView.getChildAt(0) == null) {
                                        itemsView.post {
                                            itemsView.getChildAt(0)?.requestFocus()
                                        }
                                    } else {
                                        itemsView?.getChildAt(0)?.requestFocus()
                                    }
                                }
                            }
                            channelEmptyView.text = if (state.channelContentLoading) "" else getString(R.string.empty_channel)
                            channelEmptyView.visibility = if (!state.channelContentLoading && sectionModels.isEmpty()) View.VISIBLE else View.GONE
                        }
                        else -> {
                            libraryContent.visibility = View.VISIBLE
                            channelDetailContent.visibility = View.GONE
                            playlistDetailContent.visibility = View.GONE
                        }
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
            sourceUrl = item.sourceUrl,
            createdAt = item.createdAt,
            duration = item.duration,
            isOffloaded = !item.isDownloaded,
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
            val seeAllView = sectionView.findViewById<TextView>(R.id.sectionSeeAll)
            val itemsView = sectionView.findViewById<RecyclerView>(R.id.sectionItems)
            val adapter = TvVideoCardAdapter(
                onClick = ::openVideo,
                onLongClick = ::openVideoActions,
                onFocusGained = { focusedCard -> ensureSectionVisible(sectionView, focusedCard) },
                horizontalCardWidthPx = homeCardWidthPx(),
                nextFocusUpId = if (index == 0) R.id.channelBackButton else View.NO_ID,
                nextFocusRightProvider = { pos -> 
                    if (pos == (section.items.size - 1)) R.id.sectionSeeAll else View.NO_ID 
                },
            )

            titleView.text = section.title
            seeAllView.setOnClickListener {
                viewModel.selectPlaylist(section.playlist)
            }
            seeAllView.nextFocusLeftId = R.id.sectionItems
            
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
    val playlist: PlaylistSummary,
)

private class TvVideoCardAdapter(
    private val onClick: (VideoItem) -> Unit,
    private val onLongClick: (VideoItem) -> Unit,
    private val onFocusGained: ((View) -> Unit)? = null,
    private val horizontalCardWidthPx: Int? = null,
    private val nextFocusUpId: Int = View.NO_ID,
    private val nextFocusUpProvider: ((Int) -> Int)? = null,
    private val nextFocusRightProvider: ((Int) -> Int)? = null,
) : RecyclerView.Adapter<TvVideoCardAdapter.VideoViewHolder>() {

    companion object {
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
        return VideoViewHolder(view, onClick, onLongClick, onFocusGained)
    }

    override fun onBindViewHolder(holder: VideoViewHolder, position: Int) {
        holder.bind(items[position])
        val upId = nextFocusUpProvider?.invoke(position) ?: nextFocusUpId
        if (upId != View.NO_ID) {
            holder.itemView.nextFocusUpId = upId
        }
        val rightId = nextFocusRightProvider?.invoke(position) ?: View.NO_ID
        if (rightId != View.NO_ID) {
            holder.itemView.nextFocusRightId = rightId
        }
    }

    override fun getItemCount(): Int = items.size

    class VideoViewHolder(
        itemView: View,
        private val onClick: (VideoItem) -> Unit,
        private val onLongClick: (VideoItem) -> Unit,
        private val onFocusGained: ((View) -> Unit)?,
    ) : RecyclerView.ViewHolder(itemView) {
        private val imageView = itemView.findViewById<ImageView>(R.id.cardImage)
        private val titleView = itemView.findViewById<TextView>(R.id.cardTitle)
        private val dateView = itemView.findViewById<TextView>(R.id.cardDate)
        private val badgeView = itemView.findViewById<TextView>(R.id.cardSubtitle)
        private val uploadBadgeView = itemView.findViewById<TextView>(R.id.cardUploadBadge)
        private val progressBg = itemView.findViewById<View>(R.id.cardProgressBackground)
        private val progressFill = itemView.findViewById<View>(R.id.cardProgressFill)
        private var boundItem: VideoItem? = null
        private val prefs = itemView.context.getSharedPreferences("bolttube_progress", android.content.Context.MODE_PRIVATE)

        init {
            itemView.isLongClickable = true
            itemView.setOnClickListener {
                boundItem?.let(onClick)
            }
            itemView.setOnLongClickListener {
                boundItem?.let(onLongClick)
                true
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
            dateView.text = formatCreatedDate(item.createdAt)
            
            if (item.duration > 0) {
                badgeView.text = formatDuration(item.duration.toLong())
                badgeView.visibility = View.VISIBLE
            } else {
                badgeView.visibility = View.GONE
            }

            uploadBadgeView.visibility = if (item.isOffloaded) View.VISIBLE else View.GONE
            imageView.alpha = if (item.isOffloaded) 0.5f else 1f

            try {
                val vazir = androidx.core.content.res.ResourcesCompat.getFont(itemView.context, R.font.vazir)
                titleView.typeface = vazir
                dateView.typeface = vazir
                badgeView.typeface = vazir
                uploadBadgeView.typeface = vazir
            } catch (_: Exception) {
                titleView.setTypeface(null, android.graphics.Typeface.BOLD)
            }

            Glide.with(itemView)
                .load(item.thumbnailUrl)
                .centerCrop()
                .error(android.R.color.transparent)
                .into(imageView)

            updateProgress(item.id)
        }

        private fun updateProgress(id: String) {
            val pos = prefs.getLong("progress_$id", 0)
            val dur = prefs.getLong("duration_$id", 0)

            if (dur > 0 && pos > 0) {
                progressBg.visibility = View.VISIBLE
                progressFill.visibility = View.VISIBLE
                
                val percent = (pos.toDouble() / dur.toDouble())
                progressFill.post {
                    val fullWidth = progressBg.width
                    val params = progressFill.layoutParams
                    params.width = (fullWidth * percent).toInt().coerceAtLeast(1)
                    progressFill.layoutParams = params
                }
            } else {
                progressBg.visibility = View.GONE
                progressFill.visibility = View.GONE
            }
        }

        private fun formatCreatedDate(createdAt: String): String {
            if (createdAt.isBlank()) return ""
            
            return try {
                // Remove millisecond variants to make parsing simpler for older Android versions
                val cleanDate = createdAt.split(".").firstOrNull()?.let { 
                    if (it.endsWith("Z")) it else "${it}Z" 
                } ?: createdAt

                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    val instant = try {
                        // OffsetDateTime handles +00:00 much better than Instant.parse directly
                        java.time.OffsetDateTime.parse(createdAt).toInstant()
                    } catch (e: Exception) {
                        java.time.Instant.parse(cleanDate)
                    }
                    
                    val now = java.time.Instant.now()
                    val diff = java.time.Duration.between(instant, now).toMillis()
                    val weekMillis = 7L * 24 * 60 * 60 * 1000

                    if (diff < weekMillis) {
                        val seconds = diff / 1000
                        val minutes = seconds / 60
                        val hours = minutes / 60
                        val days = hours / 24

                        when {
                            days > 0 -> "$days days ago"
                            hours > 0 -> "$hours hours ago"
                            minutes > 0 -> "$minutes minutes ago"
                            seconds > 0 -> "$seconds seconds ago"
                            else -> "Just now"
                        }
                    } else {
                        val formatter = java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd")
                            .withZone(java.time.ZoneId.systemDefault())
                        formatter.format(instant)
                    }
                } else {
                    // Simple manual parse for older devices
                    createdAt.split("T").firstOrNull() ?: ""
                }
            } catch (e: Exception) {
                // If parsing fails, just show the date part of the string
                createdAt.split("T").firstOrNull() ?: ""
            }
        }

        private fun isPersian(text: String): Boolean {
            for (char in text) {
                if (char in '\u0600'..'\u06FF') return true
            }
            return false
        }

        private fun formatDuration(totalSeconds: Long): String {
            val hours = totalSeconds / 3600
            val minutes = (totalSeconds % 3600) / 60
            val seconds = totalSeconds % 60
            return if (hours > 0) String.format("%d:%02d:%02d", hours, minutes, seconds)
            else String.format("%02d:%02d", minutes, seconds)
        }

    }
}
