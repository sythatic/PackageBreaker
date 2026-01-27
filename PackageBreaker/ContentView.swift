import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
	@State private var pkgURL: URL?
	@State private var outputURL: URL?
	@State private var logText: String = ""
	@State private var isProcessing = false
	@State private var showAlert = false
	@State private var alertMessage = ""

	var body: some View {
		VStack(spacing: 20) {
			// Header
			VStack(spacing: 8) {
				Image(systemName: "shippingbox.fill")
					.font(.system(size: 48))
					.foregroundStyle(.blue)
				Text("Package Breaker")
					.font(.title2)
					.fontWeight(.semibold)
				Text("Expand macOS installer packages")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.padding(.top)

			Divider()

			// File selection cards
			VStack(spacing: 12) {
				FileSelectionCard(
					title: "Package File",
					icon: "shippingbox",
					url: pkgURL,
					action: { pickPackage() }
				)

				FileSelectionCard(
					title: "Output Folder",
					icon: "folder",
					url: outputURL,
					action: { pickFolder() }
				)
			}
			.padding(.horizontal)

			// Extract button
			Button(action: runExtract) {
				HStack {
					Image(systemName: "arrow.down.doc.fill")
					Text("Expand Package")
						.fontWeight(.medium)
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 12)
			}
			.buttonStyle(.borderedProminent)
			.disabled(!canExtract)
			.padding(.horizontal)

			// Console output
			if !logText.isEmpty || isProcessing {
				VStack(alignment: .leading, spacing: 8) {
					HStack {
						Text("Console")
							.font(.caption)
							.fontWeight(.medium)
							.foregroundStyle(.secondary)
						Spacer()
						if isProcessing {
							ProgressView()
								.scaleEffect(0.7)
								.frame(width: 16, height: 16)
						}
					}

					ScrollViewReader { proxy in
						ScrollView {
							Text(logText)
								.font(.system(.caption, design: .monospaced))
								.frame(maxWidth: .infinity, alignment: .leading)
								.textSelection(.enabled)
								.id("logBottom")
						}
						.frame(maxHeight: 200)
						.background(Color(nsColor: .textBackgroundColor))
						.clipShape(RoundedRectangle(cornerRadius: 8))
						.onChange(of: logText) {
							withAnimation {
								proxy.scrollTo("logBottom", anchor: .bottom)
							}
						}
					}
				}
				.padding(.horizontal)
			}

			Spacer()
		}
		.frame(minWidth: 520, minHeight: 480)
		.alert("Error", isPresented: $showAlert) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(alertMessage)
		}
	}

	private var canExtract: Bool {
		pkgURL != nil && outputURL != nil && !isProcessing
	}

	// MARK: - File Picking

	private func pickPackage() {
		let panel = NSOpenPanel()
		panel.canChooseFiles = true
		panel.canChooseDirectories = false
		panel.allowsMultipleSelection = false
		panel.allowedContentTypes = [UTType(filenameExtension: "pkg") ?? .data]
		panel.message = "Select a package to expand"

		panel.begin { response in
			if response == .OK, let url = panel.url {
				pkgURL = url
				log("􀅴 Selected package: \(url.lastPathComponent)")
			}
		}
	}

	private func pickFolder() {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.canCreateDirectories = true
		panel.message = "Select where to save the package contents"

		panel.begin { response in
			if response == .OK, let url = panel.url {
				outputURL = url
				log("􀅴 Output folder: \(url.path)")
			}
		}
	}

	// MARK: - Extraction

	private func runExtract() {
		guard let pkg = pkgURL, let out = outputURL else {
			showError("􀁞 Please select both a package file and output folder.")
			return
		}

		// Verify package exists
		guard FileManager.default.fileExists(atPath: pkg.path) else {
			showError("􀁞 The selected package file no longer exists.")
			return
		}

		let pkgBaseName = pkg.deletingPathExtension().lastPathComponent
		let finalOutput = out.appendingPathComponent(
			pkgBaseName,
			isDirectory: true
		)

		// Check if output already exists
		if FileManager.default.fileExists(atPath: finalOutput.path) {
			showError(
				"􀁞 Output folder '\(pkgBaseName)' already exists. Please choose a different location or rename/delete the existing folder."
			)
			return
		}

		// Ensure parent directory exists
		do {
			try FileManager.default.createDirectory(
				at: out,
				withIntermediateDirectories: true,
				attributes: nil
			)
		} catch {
			showError(
				"􀀲 Failed to create output directory: \(error.localizedDescription)"
			)
			return
		}

		logText = ""
		isProcessing = true
		log("􀅴 Starting extraction...")
		log("􀅴 Package: \(pkg.lastPathComponent)")
		log("􀅴 Output: \(finalOutput.path)")

		Task {
			await extractPackage(pkg: pkg, output: finalOutput)
		}
	}

	private func extractPackage(pkg: URL, output: URL) async {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
		process.arguments = ["--expand-full", pkg.path, output.path]

		let outputPipe = Pipe()
		let errorPipe = Pipe()
		process.standardOutput = outputPipe
		process.standardError = errorPipe

		// Read output asynchronously
		let outputHandle = outputPipe.fileHandleForReading
		let errorHandle = errorPipe.fileHandleForReading

		Task {
			for try await line in outputHandle.bytes.lines {
				await MainActor.run {
					log("  \(line)")
				}
			}
		}

		Task {
			for try await line in errorHandle.bytes.lines {
				await MainActor.run {
					log("􀁞 \(line)")
				}
			}
		}

		do {
			try process.run()
			process.waitUntilExit()

			await MainActor.run {
				isProcessing = false

				if process.terminationStatus == 0 {
					log("􀁢 Package extracted successfully!")
					log("􀅴 Location: \(output.path)")

					// Offer to reveal in Finder
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
						NSWorkspace.shared.selectFile(
							output.path,
							inFileViewerRootedAtPath: ""
						)
					}
				} else {
					log(
						"􀀲 Extraction failed with exit code \(process.terminationStatus)"
					)
				}
			}
		} catch {
			await MainActor.run {
				isProcessing = false
				log("􀀲 Failed to run pkgutil: \(error.localizedDescription)")
			}
		}
	}

	// MARK: - Utilities

	private func log(_ message: String) {
		logText += message + "\n"
	}

	private func showError(_ message: String) {
		alertMessage = message
		showAlert = true
	}
}

// MARK: - Supporting Views

struct FileSelectionCard: View {
	let title: String
	let icon: String
	let url: URL?
	let action: () -> Void

	var body: some View {
		HStack {
			Image(systemName: icon)
				.font(.title2)
				.foregroundStyle(.blue)
				.frame(width: 32)

			VStack(alignment: .leading, spacing: 4) {
				Text(title)
					.font(.subheadline)
					.fontWeight(.medium)

				if let url = url {
					Text(url.path)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)
				} else {
					Text("􀁞 Not selected")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}

			Spacer()

			Button("Select") {
				action()
			}
			.buttonStyle(.borderedProminent)
		}
		.padding()
		.background(Color(nsColor: .controlBackgroundColor))
		.clipShape(RoundedRectangle(cornerRadius: 10))
	}
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
	static var previews: some View {
		ContentView()
	}
}
