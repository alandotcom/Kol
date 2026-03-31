import ApplicationServices

/// Read a string attribute from an AXUIElement, returning nil on failure.
func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
	var ref: CFTypeRef?
	guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
		  let str = ref as? String
	else { return nil }
	return str
}
