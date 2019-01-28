//
//  ViewController.swift
//  TheQuantizer
//
//  Created by Simon Rodriguez on 16/01/2019.
//  Copyright © 2019 Simon Rodriguez. All rights reserved.
//

import Cocoa

class DocumentViewController: NSViewController, ImageLoaderDelegate {
	
	// Ui elements.
	@IBOutlet weak var backgroundLabel: NSTextField!
	
	@IBOutlet weak var showOriginalButton: NSButton!
	@IBAction func showOriginal(_ sender: NSButton) {
		
		if imageView.image == document.originalImage {
			imageView.image = document.newImage
		} else {
			imageView.image = document.originalImage
		}
		
	}
	
	// Colors
	
	@IBOutlet weak var colorsSlider: NSSlider!
	@IBOutlet weak var colorsStepper: NSStepper!
	@IBOutlet weak var colorsLabel: NSTextField!
	@IBOutlet weak var ditheredCheck: NSButton!
	private var colorsCount = 256
	@IBAction func colorsSliderChanged(_ sender: NSSlider) {
		colorsCount = Int(round(pow(2, sender.doubleValue)))
		colorsLabel.cell?.stringValue = "\(colorsCount)"
		colorsStepper.integerValue = colorsCount
		updateCompressedVersion()
	}
	
	@IBAction func colorsStepperChanged(_ sender: NSStepper) {
		colorsCount = sender.integerValue
		colorsLabel.cell?.stringValue = "\(colorsCount)"
		colorsSlider.doubleValue = log2(Double(colorsCount))
		updateCompressedVersion()
	}
	
	@IBAction func ditheredCheckChanged(_ sender: NSButton) {
		updateCompressedVersion()
	}
	
	@IBOutlet weak var noAlphaCheck: NSButton!
	@IBAction func noAlphaChecked(_ sender: NSButton) {
		updateCompressedVersion()
	}
	// Algorithms.
	private var optionId = 0
	@IBAction func methodMenuChanged(_ sender: NSPopUpButton) {
		optionId = sender.selectedTag()
		updateCompressedVersion()
	}
	
	// Display options.
	
	@IBOutlet weak var smoothingCheck: NSButton!
	@IBAction func smoothingCheckChanged(_ sender: NSButton) {
		imageView.smoothed = sender.state == .on
	}
	
	@IBOutlet weak var scaleSlider: NSSlider!
	@IBOutlet weak var scaleStepper: NSStepper!
	@IBOutlet weak var scaleLabel: NSTextField!
	
	@IBAction func scaleSliderChanged(_ sender: NSSlider) {
		scaleLabel.cell?.stringValue = sender.doubleValue.string(fractionDigits: 1) + "x"
		scaleStepper.doubleValue = sender.doubleValue
	}
	
	@IBAction func scaleStepperChanged(_ sender: NSStepper) {
		var currentValue = sender.doubleValue
		// Are we increasing or decreasing.
		if currentValue > scaleSlider.doubleValue {
			currentValue = floor(scaleSlider.doubleValue + 1)
		} else {
			currentValue = ceil(scaleSlider.doubleValue - 1)
		}
		// Safety clamping.
		currentValue = max(scaleSlider.minValue, min(scaleSlider.maxValue, currentValue))
		
		scaleLabel.cell?.stringValue = currentValue.string(fractionDigits: 1) + "x"
		scaleSlider.doubleValue = currentValue
		sender.doubleValue = currentValue
	}
	
	
	// Image view.
	
	
	@IBOutlet weak var imageView: InteractiveImageView!
	@IBOutlet weak var progressIndicator: NSProgressIndicator!
	@IBOutlet weak var infoLabel: NSTextField!
	
	
	override func viewDidLoad() {
		super.viewDidLoad()
		infoLabel.cell!.stringValue = "No image loaded."
		let filter = NSEvent.EventTypeMask.leftMouseDown.union(.leftMouseUp)
		showOriginalButton.cell!.sendAction(on: filter)
		imageView.delegate = self
	}
	
	
	private var document = ImageDocument()
	
	
	override func viewWillAppear() {
		if let aDocument = self.view.window?.windowController?.document as? ImageDocument {
			document = aDocument
			
			imageView.image = document.originalImage
			if let _ = document.originalImage {
				backgroundLabel.isHidden = true
			}
			infoLabel.cell!.stringValue = document.displayName + ": \(document.originalSize) bytes"
			updateCompressedVersion()
		}
	}
	
	func loadItem(at path: URL) {
		NSDocumentController.shared.openDocument(withContentsOf: path, display: true, completionHandler: {_,_,_ in })
	}
	
	
	private let semaphore = DispatchSemaphore(value: 1)
	
	func updateCompressedVersion(){
		guard let originalImg = document.originalImage else {
			return
		}
		
		
		let ditheringEnabled = ditheredCheck!.state == .on
		let noAlphaEnabled = noAlphaCheck!.state == .on
		
		DispatchQueue.global(qos: .userInteractive ).async {
			// Wait for the compressors to be available.
			self.semaphore.wait()
			
			// Start animation.
			DispatchQueue.main.async {
				self.progressIndicator.startAnimation(self)
			}
			
			
			
			let w = Int(originalImg.size.width)
			let h = Int(originalImg.size.height)
			// Duplicate buffer.
			let bufferCopy = UnsafeMutablePointer<UInt8>.allocate(capacity: w*h*4)
			for i in 0..<w*h {
				let baseInd = 4*i
				bufferCopy[baseInd+0] = self.document.originalData[baseInd+0]
				bufferCopy[baseInd+1] = self.document.originalData[baseInd+1]
				bufferCopy[baseInd+2] = self.document.originalData[baseInd+2]
				bufferCopy[baseInd+3] = noAlphaEnabled ? 255 : self.document.originalData[baseInd+3]
			}
			
			// Do the stuuuuff.
			var compressedImg : CompressedImage? = nil
			switch self.optionId {
			case 0:
				compressedImg = PngQuantCompressor.compress(buffer: bufferCopy, w: w, h: h, colorCount: self.colorsCount, shouldDither: ditheringEnabled)
				break
			case 1:
				compressedImg = PosterizerCompressor.compress(buffer: bufferCopy, w: w, h: h, colorCount: self.colorsCount, shouldDither: ditheringEnabled)
				break
			case 2:
				compressedImg = PngQCompressor.compress(buffer: bufferCopy, w: w, h: h, colorCount: self.colorsCount, shouldDither: ditheringEnabled)
				break
			default:
				break
			}
			
			bufferCopy.deallocate()
			
			// If the compression succeeded
			if let newImg = compressedImg {
				
				// Compute size gain, write file to disk.
				let pc = Int(round((Double(self.document.originalSize) - Double(newImg.size))/Double(self.document.originalSize) * 100))
				
				let data = Data(bytes: newImg.data, count: newImg.size)
				newImg.data.deallocate()
				
				let pathComponent = self.document.displayName + UUID().uuidString + ".png"
				var tempPath = URL(fileURLWithPath: NSTemporaryDirectory())
				tempPath.appendPathComponent(pathComponent)
				try? data.write(to: tempPath)
				self.document.newImage = NSImage(contentsOf: tempPath)
				self.document.newData = data
				try? FileManager.default.removeItem(at: tempPath)
				
				
				// Update GUI.
				DispatchQueue.main.async {
					self.infoLabel.cell!.stringValue = self.document.displayName + ": \(newImg.size) bytes (saved \(pc)% of \(self.document.originalSize) bytes)"
					self.imageView.image = self.document.newImage
					self.progressIndicator.stopAnimation(self)
					// Release the compressors.
					self.semaphore.signal()
				}
			} else {
				// Else just stop.
				DispatchQueue.main.async {
					self.progressIndicator.stopAnimation(self)
					self.semaphore.signal()
				}
			}
			
			
		}
		
	}
	

	override var representedObject: Any? {
		didSet {
		// Update the view, if already loaded.
		}
	}


}

