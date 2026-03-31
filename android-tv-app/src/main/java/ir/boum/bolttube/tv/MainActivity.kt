package ir.boum.bolttube.tv

import android.os.Bundle
import android.widget.Button
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.commit

class MainActivity : FragmentActivity(), ServerConfigDialogFragment.Listener {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        findViewById<Button>(R.id.serverButton).setOnClickListener {
            (supportFragmentManager.findFragmentById(R.id.rowsContainer) as? TvBrowseFragment)
                ?.openServerDialog()
        }

        if (savedInstanceState == null) {
            supportFragmentManager.commit {
                setReorderingAllowed(true)
                replace(R.id.rowsContainer, TvBrowseFragment())
            }
        }
    }

    override fun onServerSubmitted(url: String) {
        val fragment = supportFragmentManager.findFragmentById(R.id.rowsContainer) as? TvBrowseFragment
        fragment?.submitServerUrl(url)
    }
}
