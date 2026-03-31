package ir.boum.bolttube.tv

import android.app.Dialog
import android.content.Context
import android.os.Bundle
import android.util.TypedValue
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import androidx.appcompat.app.AppCompatDialog
import androidx.fragment.app.DialogFragment

class ServerConfigDialogFragment : DialogFragment() {

    interface Listener {
        fun onServerSubmitted(url: String)
    }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val context = requireContext()
        val content = LayoutInflater.from(context).inflate(R.layout.dialog_server_config, null)
        val input = content.findViewById<EditText>(R.id.serverInput)
        val cancelButton = content.findViewById<Button>(R.id.cancelButton)
        val saveButton = content.findViewById<Button>(R.id.saveButton)

        input.setText(requireArguments().getString(ARG_CURRENT_URL).orEmpty())
        input.setSelection(input.text.length)

        fun submit() {
            (activity as? Listener)?.onServerSubmitted(input.text.toString())
            dismiss()
        }

        cancelButton.setOnClickListener { dismiss() }
        saveButton.setOnClickListener { submit() }
        input.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                submit()
                true
            } else {
                false
            }
        }

        val dialog = AppCompatDialog(context, R.style.Theme_BoltTubeTV_Dialog)
        dialog.setContentView(content)
        dialog.setCanceledOnTouchOutside(true)
        dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE)
        dialog.window?.setLayout(dp(context, 520), ViewGroup.LayoutParams.WRAP_CONTENT)

        input.post {
            input.requestFocus()
        }

        input.nextFocusDownId = R.id.saveButton
        cancelButton.nextFocusRightId = R.id.saveButton
        saveButton.nextFocusLeftId = R.id.cancelButton
        saveButton.nextFocusUpId = R.id.serverInput
        cancelButton.nextFocusUpId = R.id.serverInput

        return dialog
    }

    private fun dp(context: Context, value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            context.resources.displayMetrics,
        ).toInt()
    }

    companion object {
        private const val ARG_CURRENT_URL = "current_url"

        fun newInstance(currentUrl: String): ServerConfigDialogFragment {
            return ServerConfigDialogFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_CURRENT_URL, currentUrl)
                }
            }
        }
    }
}
