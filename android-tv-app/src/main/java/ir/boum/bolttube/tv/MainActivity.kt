package ir.boum.bolttube.tv

import android.os.Bundle
import android.view.View
import android.widget.TextView
import androidx.fragment.app.FragmentActivity
import androidx.activity.viewModels
import androidx.fragment.app.commit
import androidx.fragment.app.commitNow
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.launch

class MainActivity : FragmentActivity(), ServerConfigDialogFragment.Listener {
    private val viewModel: TvViewModel by viewModels()
    private lateinit var channelAdapter: SidebarChannelAdapter
    private lateinit var homeButton: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        (supportFragmentManager.findFragmentByTag("server_config") as? ServerConfigDialogFragment)?.let { dialog ->
            supportFragmentManager.commitNow {
                remove(dialog)
            }
        }

        channelAdapter = SidebarChannelAdapter { channel ->
            viewModel.selectChannel(channel)
        }

        findViewById<RecyclerView>(R.id.sidebarChannels).apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            adapter = channelAdapter
        }

        homeButton = findViewById<TextView>(R.id.sidebarHome).apply {
            setOnClickListener {
                viewModel.clearSelectedChannel()
                viewModel.refreshAll()
            }
        }

        findViewById<TextView>(R.id.sidebarSettings).setOnClickListener {
            (supportFragmentManager.findFragmentById(R.id.rowsContainer) as? TvBrowseFragment)
                ?.openServerDialog()
        }

        if (savedInstanceState == null) {
            supportFragmentManager.commit {
                setReorderingAllowed(true)
                replace(R.id.rowsContainer, TvBrowseFragment())
            }
        }

        homeButton.post {
            if (!homeButton.hasFocus()) {
                homeButton.requestFocus()
            }
        }

        observeSidebar()
    }

    override fun onResume() {
        super.onResume()
        viewModel.refreshAll()
    }

    override fun onServerSubmitted(url: String) {
        val fragment = supportFragmentManager.findFragmentById(R.id.rowsContainer) as? TvBrowseFragment
        fragment?.submitServerUrl(url)
    }

    private fun observeSidebar() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiState.collect { state ->
                    channelAdapter.submit(state.channels, state.selectedChannel?.id)
                }
            }
        }
    }
}

private class SidebarChannelAdapter(
    private val onClick: (ChannelSummary) -> Unit,
) : RecyclerView.Adapter<SidebarChannelAdapter.SidebarChannelViewHolder>() {
    private val items = mutableListOf<ChannelSummary>()
    private var selectedId: Int? = null

    fun submit(newItems: List<ChannelSummary>, selectedId: Int?) {
        items.clear()
        items.addAll(newItems)
        this.selectedId = selectedId
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: android.view.ViewGroup, viewType: Int): SidebarChannelViewHolder {
        val view = android.view.LayoutInflater.from(parent.context)
            .inflate(R.layout.item_sidebar_channel, parent, false)
        return SidebarChannelViewHolder(view, onClick)
    }

    override fun onBindViewHolder(holder: SidebarChannelViewHolder, position: Int) {
        holder.bind(items[position], items[position].id == selectedId)
    }

    override fun getItemCount(): Int = items.size

    class SidebarChannelViewHolder(
        itemView: android.view.View,
        private val onClick: (ChannelSummary) -> Unit,
    ) : RecyclerView.ViewHolder(itemView) {
        private val titleView = itemView.findViewById<TextView>(R.id.sidebarChannelTitle)
        private val metaView = itemView.findViewById<TextView>(R.id.sidebarChannelMeta)
        private var boundItem: ChannelSummary? = null

        init {
            itemView.setOnClickListener {
                boundItem?.let(onClick)
            }
        }

        fun bind(item: ChannelSummary, selected: Boolean) {
            boundItem = item
            titleView.text = item.name
            metaView.text = ""
            metaView.visibility = View.GONE
            itemView.isSelected = selected
            itemView.nextFocusRightId = R.id.rowsContainer
        }
    }
}
