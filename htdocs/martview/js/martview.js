/* $Id$
=head1 MartView client side JavaScript functions

The following functions are used on the client side of a MartView request.
Most are called in response to user actions (form element event handlers),
but a few are called on page load as well.

=cut

=head2 updateMenuPushactions()

Main function for doing pushaction-updating of secondary menus when
primary menu changes. All information is stored in the big hash-struct
at the bottom of the filter panel. The function traverses the possibly
recursive pushaction-config (flattened in the hash), updates the 
secondary menu and calls itself to also process downstream menus if needed.

=cut

*/
function updateMenuPushactions(menu, pushActionsOfMenu, prevValueOfMenu) {   
    // Get pushaction-info corresponding to the selected value of this menu, if any	
    if(menu.selectedIndex < 0) {
	//alert("ATTN, no value selected for menu " + menu.name + ", selectedIndex = " + menu.selectedIndex + ", can't do pushaction-thing now");
	return false;
    }
    var menu_value = menu.options[menu.selectedIndex].value;
    var pushActionInfo;
    
    //alert (menu.name + '  -  '+menu_value);
	    
    if(pushActionsOfMenu && pushActionsOfMenu[menu.name]) {
	//	alert ('Its there');
	pushActionInfo = pushActionsOfMenu[menu.name][menu_value];
    }
    if(!pushActionInfo) {
	//alert('FASLE');
	return false; // return w/o doing anything if there's no pa-info available for this menu
    }
    
    //alert("I'm here");
    // Find all secondary menus to update given the value of the primary menu
    for(var menu2_name in pushActionInfo) {
		var menu2 = document.mainform.elements[menu2_name];
		//alert("Have secondary menu to update: " + menu2_name);
	
		if(!menu2) {
		    continue;
		}
		if(prevValueOfMenu)
		{
			//alert(prevValueOfMenu[menu2_name]);
		}
		//alert('DBLENGTH '+pushActionInfo[menu2_name].length+ ' DB: '+pushActionInfo[menu2_name][0][0]);
		var pushActionLoopLength = pushActionInfo[menu2_name].length;

		for(var i=0;i < pushActionLoopLength; i++) {
			//option_name = option_names[i];
			//alert(i + " "+ pushActionInfo[menu2_name][i][1]);
		    optionName = pushActionInfo[menu2_name][i][0];
		    optionDisplayName = pushActionInfo[menu2_name][i][1];
		    var option = new Option(optionDisplayName, optionName);
		    menu2.options[i] = option;
	   	 	if(prevValueOfMenu && prevValueOfMenu[menu2_name] == optionDisplayName) {
			//	alert ('SELECTED')
				menu2.options[i].selected = true;
	    		}
		}	
	
		// Call this function again, to recursively process pushaction-config
		// of arbitrary depth, but only if there's actually pushaction-info
		// available (to avoid an infinite loop here, you see..)
		
		if(pushActionsOfMenu[menu2_name]) {
		    //alert("Have tertiary menu to update, calling function again for menu " + menu2_name);
	    		//alert ('yes '+  menu2_name);
		    updateMenuPushactions(menu2, pushActionsOfMenu, prevValueOfMenu);
		}
    }
}

function changeRadioStatus (siblingNodes, thisName,  attListName)
{
        alert ('here ahahah');
        for(var i=0; i<siblingNodes.length; i++)
        {
                if (siblingNodes[i] == thisName) continue;
                if(siblingNodes[i].tagName == 'input' && siblingNodes[i].type == 'hidden' && siblingNodes[i].value == 'on')
                {
                        siblingNodes[i].value = 'off';
                        removeFromSummaryPanelList(attListName, siblingNodes[i].name);
                }
                else if(siblingNodes[i].type == 'radio')
                {
                        removeFromSummaryPanelList(attListName, siblingNodes[i].name);
                        siblingNodes[i].checked = false;
                        siblingNodes[i].onchange();
                }
        }

}

function addOnceTouchedParam (onceTouchedParamName)
{
	//alert (onceTouchedParamName);
	
	var hiddenParam = document.createElement("input");
	hiddenParam.type  = "hidden";
   	hiddenParam.name  = onceTouchedParamName;

     document.mainform.appendChild(hiddenParam);
}


/* 

=head2 addDatasetParamToForm()

Add dataset name to the dataset-list hidden param. This in effect adds the dataset
in question to the Mart query. Also sets the necessary flags to make the correct
panel come into focus on the main display and stuff.

=cut

*/
function addDatasetParamToForm(dsetName) {
    	//alert('Adding dset-name '+dsetName+' to dataset-param');
   	// Add hidden dataset parameter to form. This gets combined with existing parameters
    	// of the same name, to form the list of datasets currently in the query.
	addHiddenFormParam("dataset", document.mainform, dsetName);

    	// Set filterpanel + corresponding portion of left summary menu to expanded-status,
    	// so the new dataset gets immediate focus on both summary and main panels.
    	var visibleStatusParamName = 'dataset.'+dsetName+'__summary__visibility';
	var visibleStatusParam = document.mainform[visibleStatusParamName];
    	// Probably need to create this param from scratch
	//alert('Visibility param: '+visibleStatusParamName+'  '+visibleStatusParam);
    	if(!visibleStatusParam) 
    	{
		addHiddenFormParam(visibleStatusParamName, document.mainform, 'show');
    	}
    	document.mainform['mart_mainpanel__current_visible_section'].value  = dsetName+'__infopanel';
    	document.mainform['summarypanel__current_highlighted_branch'].value = dsetName+'__summarypanel_datasetbranch';
}


/* 

=head2 resetResultsPanel()

Delete the div containing results preview and export menu. This is done whenever
filters/attributes are modified by the user which renders the existing results 
obsolete, so he has to get fresh results by clicking the Results button.

=cut

*/
function resetResultsPanel() {
    // Remove node if it exists and change results-button accordingly
    var resultsPanelElt = document.getElementById('resultspanel');
    if(resultsPanelElt) {
	//alert('Removing resultspanel node '+resultsPanelElt);
	resultsPanelElt.parentNode.removeChild(resultsPanelElt);
	visibility('get_results', 'show');
	visibility('show_results', 'hide');
    }
}

/*

=head2 addToSummaryPanelList()

Update filter or attribute list in summary panel when user enables a filter. The short
internal name gets added to the hidden-param list, the longer display name gets shown
in the list itself. Items only get added to the list if they aren't on it already.

  See also companion function below to remove an item from a summary-list.

=cut

*/
function addToSummaryPanelList (listContainerId, name, displayName, value) {
    resetResultsPanel(); // existing results no longer valid, as user changed query parameters
    
    // alert('Adding item '+name+' Container: '+listContainerId+' DISPL: ' + displayName +' VALUE: ' + value );

    // Get element containing the list we want to update
    var listContainerElt = document.getElementById(listContainerId);

    // Check if the 'no items configured' dummy listitme is present, remove if needed
    var spans = listContainerElt.getElementsByTagName('span');
    if(spans.length > 1) {
	//alert('Removing existing count-note w/ innerHTML='+spans[1].innerHTML);
	listContainerElt.removeChild(spans[1]);
    }


    var firstDivChildElt = listContainerElt.getElementsByTagName('div')[0];
    
    
    if(firstDivChildElt && firstDivChildElt.innerHTML.match(/None selected/)) {
	//alert('got dummy no-configured child div in container, removing: '+firstDivChildElt.innerHTML);
	listContainerElt.removeChild(firstDivChildElt);
    }

    // Check if item is already on the list, in which case it doesn't need to be added!
    //alert('<input> elts in container='+listContainerElt.getElementsByTagName('input'));
    var existingItemElt = findElementWithValue(listContainerElt.getElementsByTagName('input'), name);
    if(existingItemElt) {
	//alert('Item '+name+' is already on list '+listContainerId+', removing before re-adding');
	listContainerElt.removeChild(existingItemElt.parentNode);
    }
	
    // Add  entry to the visible list as div, containing both visible display namd and hidden param
    // The item needs some onclick actions to highlight the corresponding filter-container on main panel
    var listItem  = document.createElement("div");
    
    if(value) {
	listItem.innerHTML = displayName + ': '+value;
    }
    else {
	listItem.innerHTML = displayName;
    }
	
    	//var first_dataset = document.mainform.datasetmenu_3.value;
    	var first_dataset;
    	var dsNames = getElementsByName_local('dataset');
	if(dsNames)
	{
		first_dataset = dsNames[0].value;
		//alert(first_dataset);
	}
	    
    if (listContainerId.match(first_dataset)) 
    {
		if(value)
		{
			listItem.className = 'mart_summarypanel_listitem3';
		}	
		else
		{
			listItem.className = 'mart_summarypanel_listitem';
		}
    }
    else 
    {
	
		if(value)
		{
			listItem.className = 'mart_summarypanel_listitem4';
		}	
		else
		{
			listItem.className = 'mart_summarypanel_listitem2';
		}
    
    }

    
	parentPanelId = listContainerId.replace(/list$/,'panel');
    	//alert("Showing section w/ ID "+parentPanelId+' on main panel');
	// highlighting with yellow box and changing current visible section logic
    	//listItem.onclick   = function() {
	//showPanelHideSiblings(parentPanelId);
	//highlightPanelSection(name+'__container'); 
    	//}
    	
    //alert("LIST ITEM = "+listItem.className + "LIST CONTAINER ELT = "+listContainerElt.id);
    	listContainerElt.appendChild(listItem);

    // Add hidden parameter entry to div, to get list entry into session.
    addHiddenFormParam(listContainerId, listItem, name);
}

/*

=head2 removeFromSummaryPanelList()

Remove an item from the summary-tree list. Can either be a filter or
attribute name. Both the visible list item and the hidden-param entry
are removed in the operation.

=cut

*/
function removeFromSummaryPanelList(listContainerId,name) {
    	//alert("Removing 1 "+name+" from summary list "+listContainerId);
    	resetResultsPanel(); // existing results no longer valid, as user changed query parameters
    	//alert("Removing 2 "+name+" from summary list "+listContainerId);
	// Get element containing the list we want to update
    	var listContainerElt = document.getElementById(listContainerId);

	// Iterate through list until we find the input-param we want, then remove the div it lives in
    	var elt2remove = findElementWithValue(listContainerElt.getElementsByTagName('input'), name);
    	if(elt2remove != false) 
    	{
		listContainerElt.removeChild(elt2remove.parentNode);
    	}
    
    	// Check if this action removed the last entry in a set of <input> elements. If so, add
    	// a dummy element w/ whitespace to document, to get around a problem with the session-stored
    	// value getting 'stuck'.
    	if(listContainerElt.getElementsByTagName('input').length == 0) 
	{
		//alert('Ooops, removed last input-elt in list. Adding dummy elt');
	
		//addHiddenFormParam(listContainerId, listContainerElt, ' ');
		//addToSummaryPanelList(listContainerId,"dummy","[None selected]" );

		var listItem  = document.createElement("div");
		listItem.innerHTML = "[None selected]";
		//var first_dataset = document.mainform.datasetmenu_3.value;
		var first_dataset;
    		var dsNames = getElementsByName_local('dataset');
		if(dsNames)
		{
			first_dataset = dsNames[0].value;
			//alert(first_dataset);
		}
	
	
		if (listContainerId.match(first_dataset)) 
		{
			if (name.match(/.*?__filter.*/))  	// its last filter
			{
				listItem.className = 'mart_summarypanel_listitem3';
			}
			else 						// its an attribute, last
			{
				listItem.className = 'mart_summarypanel_listitem';
			}			
    		}
	    	else 
		{
			if (name.match(/.*?__filter.*/))  	// its last filter
			{
				listItem.className = 'mart_summarypanel_listitem4';
			}
			else 						// its an attribute, last
			{
				listItem.className = 'mart_summarypanel_listitem2';
			}
		}
		listContainerElt.appendChild(listItem);
		addHiddenFormParam(listContainerId, listItem, 'dummy'); ///using the term dummy instead of mummi's blank space, to make it clear enough
	//	alert("Removing 3 "+name+" from summary list "+listContainerId);
    }
}

/*

=head2 addHiddenFormParam()

Utility function to add a hidden parameter to the mainform. Only adds param if 
it isn't already present in the form (prevents duplicates from arising).

=cut

*/
function addHiddenFormParam(paramName, parentElt, paramValue) {
    // First make sure this name/value pair doesn't exist already 
    
	var existingParamElts = getElementsByName_local(paramName);
	var loop_length = existingParamElts.length; // vv important thing in JS, for DOM API. speeds up 
    	for(var i=0; i<loop_length; i++) 
    	{
		if(existingParamElts[i].value == paramValue) 
		{
	    		//alert('param name '+paramName+' w/ value '+paramValue+' already exists, not adding a new one');	    
	    		return;
		}
    	}

/* SOLUTION 1 that works
    var existingParamElts = document.getElementsByTagName("input");
    for(var j=0; j<existingParamElts.length; j++) 
    {
    		if(existingParamElts[j].getAttribute("name") == paramName) 
    		{
    			//alert('NAME: '+paramName+ '------ VALUE: ' +existingParamElts[j].value + ' AND'+ paramValue);
    			if(existingParamElts[j].value == paramValue)
    			{
    				//alert('ALREADY EXISTS, not adding');
    				return;
    			}
    		}
    }
    
*/  
 
    // Then create the param and append to the 
    //alert('param name '+paramName+' w/ value '+paramValue+' already exists, not adding a new one');	    
	var hiddenParam = document.createElement("input");
	hiddenParam.type  = "hidden";
   	hiddenParam.name  = paramName;
	if(paramValue) { hiddenParam.value = paramValue; }
//	alert(hiddenParam.name);
     parentElt.appendChild(hiddenParam);	
}

/*

=head2 addorReplaceHiddenFormParam()

Utility function to add a hidden parameter to the mainform. If 
it is already present in the form it is replaced.

=cut

*/
function addOrReplaceHiddenFormParam(paramName, parentElt, paramValue, oldParamValue) {
    // First make sure this name doesn't exist already 
    var existingParamElts = getElementsByName_local(paramName);
    var loop_length = existingParamElts.length; // vv important thing in JS, for DOM API. speeds up 
    if (loop_length > 0) 
    {
    		// Already exists? Replace.
	    	for(var i=0; i<loop_length; i++) 
	    	{
			//alert(i+': Checking hidden param '+paramName+', value '+existingParamElts[i].value);
			// Might want to only remove params with a certain value, not all of them
			if(oldParamValue && existingParamElts[i].value != oldParamValue) 
			{
		    		continue;
			}
    			existingParamElts[i].value = paramValue;
		    	return;
   		}
   	}
	// Doesn't already exist? Add.
	addHiddenFormParam(paramName, parentElt, paramValue);        
}

/*

=head2 removeHiddenFormParam()

Utility method for removing a certain hidden param/value pair from mainform,
if present.

=cut 

*/
function removeHiddenFormParam(paramName, paramValue) {

	//alert('removing    ' + paramName);
	var existingParamElts = getElementsByName_local(paramName);
    	var loop_length = existingParamElts.length; // vv important thing in JS, for DOM API. speeds up 
	
	for(var i=0; i<loop_length; i++) 
    	{
		if (!paramValue) // for removing 'dataset', when we change e.g schema menu, or datasets
		{
			//alert ('DS removal');
			existingParamElts[i].parentNode.removeChild(existingParamElts[i]);
		}
		
		// Might want to only remove params with a certain value, not all of them
		if (paramValue && existingParamElts[i].value == paramValue) // for removing filts
    		{
			//alert ('filts removal');
    			existingParamElts[i].parentNode.removeChild(existingParamElts[i]);
    			//i--;  // Array will have shuffled to the left by one. have problem with IE/Safari here with i--
   			//loop_length--; // Array will have reduced in length by one. have problem with IE/Safari here l_l--
    			//return;
    		}    		
    }        
}

/*

=head2 getElementsByName_local()

Utility function which replaces document.getElementsByName(paramName)
as the said call, doesnt seem to be working for IE

=cut

*/

function getElementsByName_local(paramName)
{
	var existingParamElts = document.getElementsByTagName("input");
    	var arr = new Array();
    	var loop_length = existingParamElts.length; // vv important thing in JS, for DOM API. speeds up 
    	for(i = 0,iarr = 0; i < loop_length; i++) 
    	{
          if (existingParamElts[i].getAttribute("name") == paramName)
		{
			arr[iarr] = existingParamElts[i];
               iarr++;
          }
	}
	// Textareas are not inputs, unfortunately, so we have to search for them separately.
	existingParamElts = document.getElementsByTagName("textarea");
    	var loop_length = existingParamElts.length; // vv important thing in JS, for DOM API. speeds up 
    	for(i = 0,iarr = 0; i < loop_length; i++) 
    	{
          if (existingParamElts[i].getAttribute("name") == paramName)
		{
			arr[iarr] = existingParamElts[i];
               iarr++;
          }
	}
	return arr;
}

/*
=head2 resetSummaryPanelCount()

For updating summary panel count to N/A, if any filters are changed

=cut

*/

function resetSummaryPanelCount(dset_prefix)
{
	var summaryCountElt;
	var first_dataset;
    	var dsNames = getElementsByName_local('dataset');
	if(dsNames)
	{
		first_dataset = dsNames[0].value;
		//alert(dset_prefix + '====' + first_dataset);		
		//alert(first_dataset);
		if(dset_prefix.match(first_dataset))
		{
			summaryCountElt = document.getElementById('summarypanel_filter_count_1');
		}
		else
		{
			summaryCountElt = document.getElementById('summarypanel_filter_count_2');
		}
	
		if(summaryCountElt)
		{
			summaryCountElt.innerHTML = ' ';
		}
	}	
}

/*

=head2 waitingMutex()

For IE DOM complete specific waiting

=cut

*/

var filtersList = new Array();
var index=0;
function waitingMutex()
{
	if(document.readyState == "complete")
	{
		for (var i =0; i < index; i++)
		{
			enableFiltersUpdateSummaryPanelExecute(filtersList[i]);
		}
		index=0;		
	}
	else
	{
		setTimeout("waitingMutex()",50);
	}

}

/*

=head2 enableFiltersUpdateSummaryPanel()

Updating Sumamry panel and adding the check boxex for filters, when 
results are requested. This call gets deferred for IE, due to 
Operation Aborted errors by IE, however gets called in the flow
for other browsers.
=cut

*/

function enableFiltersUpdateSummaryPanel (filterCollectionEltId)
{
	if(filterCollectionEltId == 'dummy') {	return; }
	var browserInfo = new Array();
	browserInfo = detectBrowserProperties();
	if(browserInfo[0] == "Explorer")
	{		
		filtersList[index++] = filterCollectionEltId;
		// waiting resposibility is on the shoulders of first element only
		// others add them their ID and go away, ans first member does the work
		// for all of them when channels are clear
		if(index <= 1) 
		{
			waitingMutex();	
		}
	}
	else
	{		
		enableFiltersUpdateSummaryPanelExecute(filterCollectionEltId);
	}
	
}

/*

=head2 enableFiltersUpdateSummaryPanelExecute()

Updating Sumamry panel and adding the check boxex for filters, when 
results are requested. This call gets deferred for IE, due to 
Operation Aborted errors by IE, however gets called in the flow
for other browsers.
=cut

*/
 
function enableFiltersUpdateSummaryPanelExecute(filterCollectionEltId) 
{
	var filtersInContainer = getFiltersInContainer(filterCollectionEltId);
    	var dset_prefix = filterCollectionEltId.match(/^.+__/)[0];
   	addHiddenFormParam(dset_prefix+'filtercollections',document.mainform, filterCollectionEltId);	
   	var hasFilter = 0;
    	for(filterName in filtersInContainer) 
    	{
		// Get element containing the list we want to update
		var listContainerId = dset_prefix+'filterlist';
    		var name = filterName;
	    	var displayName = filtersInContainer[filterName][0];
    		var value = filtersInContainer[filterName][1];
    
    		var listContainerElt = document.getElementById(listContainerId);

    		// Check if the 'no items configured' dummy listitme is present, remove if needed
    		var spans = listContainerElt.getElementsByTagName('span');
    		if(spans.length > 1) 
    		{
			//alert('Removing existing count-note w/ innerHTML='+spans[1].innerHTML);
			listContainerElt.removeChild(spans[1]);
    		}


    		var firstDivChildElt = listContainerElt.getElementsByTagName('div')[0];
    		if(firstDivChildElt && firstDivChildElt.innerHTML.match(/None selected/)) 
    		{
			//alert('got dummy no-configured child div in container, removing: '+firstDivChildElt.innerHTML);
			listContainerElt.removeChild(firstDivChildElt);
    		}	

    		// Check if item is already on the list, in which case it doesn't need to be added!
    		//alert('<input> elts in container='+listContainerElt.getElementsByTagName('input'));
    		var existingItemElt = findElementWithValue(listContainerElt.getElementsByTagName('input'), name);
    		if(existingItemElt) 
    		{
			//alert('Item '+name+' is already on list '+listContainerId+', removing before re-adding');
			listContainerElt.removeChild(existingItemElt.parentNode);
    		}
	
    		// Add  entry to the visible list as div, containing both visible display namd and hidden param
    		// The item needs some onclick actions to highlight the corresponding filter-container on main panel
    		var listItem  = document.createElement("div");
    		if(value) 
    		{
			listItem.innerHTML = displayName + ': '+value;
    		}
    		else 
    		{
			listItem.innerHTML = displayName;
    		}
	
    		var first_dataset = document.mainform.datasetmenu_3.value;
    		if (listContainerId.match(first_dataset)) 
    		{
			listItem.className = 'mart_summarypanel_listitem3';
    		}
    		else 
    		{
			listItem.className = 'mart_summarypanel_listitem4';
    		}
		//    listItem.className = 'mart_summarypanel_listitem';
    
    		parentPanelId = listContainerId.replace(/list$/,'panel');
    		//alert("Showing section w/ ID "+parentPanelId+' on main panel');
    		// highlighting with yellow box and changing current visible section logic
    		//listItem.onclick   = function() 
    		//{
		//	showPanelHideSiblings(parentPanelId);
		//	highlightPanelSection(name+'__container'); 
    		//}
    		listContainerElt.appendChild(listItem);

    		// Add hidden parameter entry to div, to get list entry into session.
    		addHiddenFormParam(listContainerId, listItem, name);	
    		hasFilter = 1;
	}
	
	if (hasFilter==1) {
		// Turn on the collection checkbox.
    		var checkboxElt = document.mainform.elements[filterCollectionEltId];
    		//alert('Checking checkbox '+filterCollectionCheckboxName);
    		if(!checkboxElt.checked) {
			checkboxElt.checked = 'checked'; // check the box if it's not checked already
    		}
	}

}

/*
head2 enableFiltersInCollection()

Finds all filters in this filtercollection container, checks if they have valid
values and enables them if so.

=cut

*/

function enableFiltersInCollection(filterCollectionEltId) {
    
    var filtersInContainer = getFiltersInContainer(filterCollectionEltId);
    var dset_prefix = filterCollectionEltId.match(/^.+__/)[0];
    addHiddenFormParam(dset_prefix+'filtercollections',document.mainform, filterCollectionEltId);
    
    resetSummaryPanelCount(dset_prefix);
    
    for(filterName in filtersInContainer) {
	//alert('Enabling filter '+filterName+', value='+filtersInContainer[filterName][0]);
	addToSummaryPanelList(dset_prefix+'filterlist', filterName, filtersInContainer[filterName][0],filtersInContainer[filterName][1]); 
    }
}

/*

=head2 disableFiltersInCollection()

Finds all filters in this filtercollection container and removes from the enabled-list
if they are on it.

=cut

*/
function disableFiltersInCollection(filterCollectionEltId) {
    
    var filtersInContainer = getFiltersInContainer(filterCollectionEltId);
    var dset_prefix = filterCollectionEltId.match(/^(.+)__/)[0];
    removeHiddenFormParam(dset_prefix+'filtercollections', filterCollectionEltId);
    
    resetSummaryPanelCount(dset_prefix);
    
    //alert('Disabling filters w/ values in fcollection '+filterCollectionEltId+', in dset '+dset_prefix);
        
    for(filterName in filtersInContainer) {
	removeFromSummaryPanelList(dset_prefix+'filterlist', filterName);
    }
}

/*

=head2 showPanelHideSiblings()

Set to visible state the filter/attribute panel for the specified dataset, hide all other dsets.
Iterates through all datasetpanel divs in mainpanel and checks ID & hidden-state

=cut 

*/
function showPanelHideSiblings(panelId) {
//    alert('Gotta show target panel id='+panelId);
    targetPanelDiv = document.getElementById(panelId);
    if(!targetPanelDiv) {
	return false;
    }

    parentPanelDiv = targetPanelDiv.parentNode;
    
    siblingDivs = parentPanelDiv.childNodes; // get all sibling nodes

    // Hide all sibling div's
    var loop_length = siblingDivs.length;      
    for(var i=0; i < loop_length ; i++ ) { 
	if(siblingDivs[i].nodeName != 'DIV') continue; // get div only
	//alert('Hiding dsetpanel div '+siblingDivs[i]+', id='+siblingDivs[i].id+': state='+siblingDivs[i].style.display);
	turnOff(siblingDivs[i]);
    }
    // Then show just the target panel
    // alert('Showing dsetpanel div '+targetPanelDiv+', id='+targetPanelDiv.id);
    turnOn(targetPanelDiv);
    
    // Update the hidden form-param to the ID of the currently visible panel div
//    alert('Updating current visible section ID for parent panel '+parentPanelDiv.id);
    document.mainform[parentPanelDiv.id+'__current_visible_section'].value = panelId;
   
}

// Iterate over a list of elements, check for a specific value attribute and return those that do

function findElementWithValue(elts2check, value2find) {
    var eltsFound = [];
    var loop_length = elts2check.length;
    for (var i=0; i< loop_length; i++) {
	//alert('Checking if element '+elts2check[i].name+', value='+elts2check[i].value+' should be deleted');
	if(elts2check[i].value == value2find) {
	    return elts2check[i]; // return first element found (NB ignores duplicates!)
	}
    }
    return false; // i.e. if we didn't find anything above
}

/*

=head2 getFiltersInContainer()

Get list of all filter form elements in the container-element and their displaynames.
Very very dark magic since all the different kinds of form-elements have to be 
handled.

=cut

*/
function getFiltersInContainer(containerEltId) {
    var containerElt = document.getElementById(containerEltId);
    //alert('Getting filters in container '+containerEltId+', got obj='+containerElt);
    var divs = containerElt.getElementsByTagName('div');
    var currentFilterDisplayName;
    var filterInfoOf = {};

	var loop_length = divs.length;	
    for(var i=0; i<loop_length; i++) {
	switch(divs[i].className) {
	case 'mart_filtername':
	    // Get the display name string from this div. Can't grab just the entire text
	    // contained in div, coz there might be a checkbox and stuff in there also
	    for(var p=0; p<divs[i].childNodes.length;p++) {
		if(divs[i].childNodes[p].nodeName == '#text'
		   && divs[i].childNodes[p].nodeValue 
		   && divs[i].childNodes[p].nodeValue.match(/\w/)) {
		    currentFilterDisplayName = divs[i].childNodes[p].nodeValue;
		    
		    //alert('Got valid string for filtername: '+currentFilterDisplayName);
		    break;
		}
	    }
	    // If we got here, then it's probably inside an acronym. Read that instead.
	    for(var p=0; p<divs[i].childNodes.length;p++) {
		if(divs[i].childNodes[p].nodeName == 'a' || divs[i].childNodes[p].nodeName == 'A') {
		var acroNodeValue = divs[i].childNodes[p].innerHTML;
		if(acroNodeValue
		   && acroNodeValue.match(/\w/)) {
		    currentFilterDisplayName = acroNodeValue;
		    //alert('Got valid string for filtername: '+currentFilterDisplayName);
		    break;
	    }
		}
		}
	    break;
	case 'mart_filtervalue':
	    // The filterval-div could have a number of form elements, such as upload buttons etc.
	    // Gotta find the form-element with the filtername same as ID of the filterval-container 
	    //var childElts = divs[i].childNodes;
	    //var childElts = divs[i].getElementsByTagName('select');
	    var childElts = getElements(divs[i]);
	    //alert('Iterating over childElts list obj='+childElts+', length='+childElts.length);
	    var loop_length_1 = childElts.length;
	    var myFilterValues = [];
	    for(var j=0; j<loop_length_1; j++ ) {
		//alert('Checking if element is the actual filtervalue-elt, obj='+childElts[j]+', name='+childElts[j].name);
		if(childElts[j].name && childElts[j].name == divs[i].id) {
		    var filterValueElt = childElts[j];	    		    
		    
		    var filterValue;
		    var filterName        = filterValueElt.name;
		    var dset_prefix = filterName.match(/^.+__/)[0];
		    var filterDisplayName = currentFilterDisplayName;
		    
		    //alert('Checking if we have a filter-elt here, obj='+filterValueElt.name+' TYPE='+filterValueElt.type+ ' FDISPNAME: '+currentFilterDisplayName);
		    
		    switch(filterValueElt.type) {
		    case 'text':
			if(filterValueElt.value != '') {
			    filterValue = filterValueElt.value;
			    //filterValue = filterValueElt.innerHTML;
			    
			    filterDisplayName = currentFilterDisplayName;
			    filterInfoOf[filterName] = [filterDisplayName, filterValue];
			    continue;
			}
			break;
		    case 'select-one':
			//alert('filterValueElt.selectedIndex for select-elt '+filterValueElt.name+' is '+filterValueElt.selectedIndex);
			if(filterValueElt.selectedIndex >= 0) {
			    // Check if there's a radio-button associated with this list, then it is
			    // a complex list-type (ID or boolean). OR if this is an ID-list filter type
			    // then there's a file-upload button and/or textarea associated with it

			    //alert('Checking if I have a bool-modifier for filtername '+filterName);
			    	var boolModifierElts = getElementsByName_local(filterName+'__list');
			    	var idListTextAreaElts = getElementsByName_local(filterName+'__text');
				var idListFileUploadElts = getElementsByName_local(filterName+'__text__file');
			
				var idListFileUploadEltName = filterName+'__text__file';

			    	if(boolModifierElts.length > 0 || 
			    		idListTextAreaElts.length > 0 ||
			    		idListFileUploadElts.length > 0) {
					
								
					filterDisplayName = filterValueElt.options[filterValueElt.selectedIndex].text;
					//alert("filterName was "+filterName);
					filterName = dset_prefix+'filter.'+filterValueElt.options[filterValueElt.selectedIndex].value;
					//alert("selected index is "+filterValueElt.selectedIndex);
					//alert("selected object is "+filterValueElt.options[filterValueElt.selectedIndex]);
					//alert("selected value is "+filterValueElt.options[filterValueElt.selectedIndex].value);
					//alert("selected html is "+filterValueElt.options[filterValueElt.selectedIndex].innerHTML);
					//alert("filterName is "+filterName);
					//alert('Got complex filterlist '+filterName+' filter Display: '+filterDisplayName);
					
					var loop_length_3 = boolModifierElts.length; 
					filterValue = '[ID-list specified]';
					if(loop_length_3 > 0) 
					{
						var filterValues = [];
				    		for(z=0; z<loop_length_3; z++ ) 
				    		{
							if(boolModifierElts[z].checked) 
							{
					    			//alert('Modifier-bool for select-list is checked, setting to value='+boolModifierElts[z].value);
								//[TAG]//filterValues.push(boolModifierElts[z].value);
								var filterBoolValue = boolModifierElts[z].id; // id to display in summaryPanel for radio buttons
					                        var portions = filterBoolValue.split("____"); // filtername____Only convention as w3c forces unique id values
                                				filterBoolValue = portions[1];
								filterValues.push(portions[1]); // id to display in summaryPanel for List radio buttons
							}
				    		}
				    		// Tricky: need to add the bool-filter info as a hidden param, since it is not
				    		// present directly (i.e. only embedded in the select-list).
				    		filterValue = filterValues.join();
				    		addOrReplaceHiddenFormParam(filterName+'__list', document.mainform, filterValue);
				    		//filterValue = '[ID-list specified]';
					}
					else if(idListTextAreaElts.length > 0 && idListTextAreaElts[0].value != '') 
					{				    
				    		// Tricky here also: need to add the textarea or file-upload info to a new param
					    	// representing the real filter (from the menu).
						//alert('Got ID-list textarea, so this is an ID-list filter, name='+filterName);
						addOrReplaceHiddenFormParam(filterName+'__text', document.mainform, idListTextAreaElts[0].value);
						//alert('Added name='+filterName+'__text value='+idListTextAreaElts[0].value);

						//filterValue = '[ID-list specified]';
					}
					else if(idListFileUploadElts.length > 0 && idListFileUploadElts[0].value != '') 
					{
						//alert('Got ID-list file, so this is an ID-list filter, name='+filterName);
						addOrReplaceHiddenFormParam(filterName+'__text__file', document.mainform, idListFileUploadEltName);
						//alert('Added name='+filterName+'__text__file value='+idListFileUploadEltName);
						
						//filterValue = '[ID-list specified]';
					}
					
			    	}
			    	else {
				// just regular filter value
				//[TAG]//filterValue = filterValueElt.options[filterValueElt.selectedIndex].value;
				filterValue = filterValueElt.options[filterValueElt.selectedIndex].innerHTML;
				filterName  = filterValueElt.name;
			    }
			    filterInfoOf[filterName] = [filterDisplayName, filterValue];
			}
			//alert('Have value '+filterValue+' for filter '+filterDisplayName);
			break;

 		case 'textarea':
			//alert('filterValueElt.selectedIndex for select-elt '+filterValueElt.name+' is '+filterValueElt.selectedIndex);
			//alert('Checking if I have a bool-modifier for filtername '+filterName);
				var idListTextAreaElts = getElementsByName_local(filterName);
				var idListFileUploadElts = getElementsByName_local(filterName+'__text__file');
				var idListFileUploadEltName = filterName+'__text__file';
				
				if(idListTextAreaElts.length > 0 || idListFileUploadElts.length > 0) {

					filterDisplayName = currentFilterDisplayName;
					filterValue = '[ID-list specified]';
					
					if(idListTextAreaElts.length > 0 && idListTextAreaElts[0].value != '') 
					{				    
				    		// Tricky here also: need to add the textarea or file-upload info to a new param
					    	// representing the real filter (from the menu).
						//alert('Got ID-list textarea, so this is an ID-list filter, name='+filterName);
						addOrReplaceHiddenFormParam(filterName+'__text', document.mainform, idListTextAreaElts[0].value);
						//alert('Added name='+filterName+'__text value='+idListTextAreaElts[0].value);

					}
					else if(idListFileUploadElts.length > 0 && idListFileUploadElts[0].value != '') 
					{
						//alert('Got ID-list file, so this is an ID-list filter, name='+filterName);
						addOrReplaceHiddenFormParam(filterName+'__text__file', document.mainform, idListFileUploadEltName);
						//alert('Added name='+filterName+'__text__file value='+idListFileUploadEltName);
						
					}
					
			    	}
			     	else {
					//alert("just regular filter vals");
					// just regular filter value
					//[TAG]//filterValue = filterValueElt.options[filterValueElt.selectedIndex].value;
					filterValue = filterValueElt.options[filterValueElt.selectedIndex].innerHTML;
					filterName  = filterValueElt.name;
			    	}	
			    	filterInfoOf[filterName] = [filterDisplayName, filterValue];
			//alert('Have value '+filterValue+' for filter '+filterDisplayName);
			break;


		    case 'select-multiple':
			//alert('filterValueElt.selectedIndex for select-elt '+filterValueElt.name+' is '+filterValueElt.selectedIndex);
			if(filterValueElt.selectedIndex >= 0) {
			    //alert('Checking if I have a bool-modifier for filtername '+filterName);
			    var boolModifierElts = getElementsByName_local(filterName+'__list');
			    var idListTextAreaElts = getElementsByName_local(filterName+'__text');
				var idListFileUploadElts = getElementsByName_local(filterName+'__text__file');
			    if(boolModifierElts.length > 0 || 
			    	idListTextAreaElts.length > 0 || 
			    	idListFileUploadElts.length > 0) {
				alert('Got complex filterlist '+filterName+' not compatible with multi-selects');
			    }
			    else {
				// just regular filter value(s)
				var filterValues = [];
				for(z=0; z<filterValueElt.options.length; z++ ) {
                                        if (filterValueElt.options[z].selected){
					    //[TAG]//filterValues.push(filterValueElt.options[z].value);
					    filterValues.push(filterValueElt.options[z].innerHTML);
					}
				}
				filterInfoOf[filterName] = [filterDisplayName, filterValues.join()];
			    }
			   
			}
			//alert('Have value '+filterValue+' for filter '+filterDisplayName);
			break;
		    case 'radio':
			if(filterValueElt.checked) {
			    //alert('Bool checkbox is checked, setting to value='+filterValueElt.value);
			    //[TAG]//filterValue = filterValueElt.value;
			    filterValue = filterValueElt.id; // id to display in summaryPanel for radio buttons
			var portions = filterValue.split("____"); // filtername____Only convention as w3c forces unique id values
				filterValue = portions[1];
				//alert (portions[0]);
			    //filterValue = filterValueElt.innerHTML;
			    filterInfoOf[filterName] = [filterDisplayName, filterValue];
			    continue;
			}
			break;
			
			case 'checkbox':
				//alert( 'CHILD NAME: '+childElts[j].name+ ' CHILD VAL: '+childElts[j].value);
				//filterValue = childElts[j].value;
				if(childElts[j].checked)
				{
					//[TAG]//myFilterValues.push(childElts[j].value);
					myFilterValues.push(childElts[j].id); // id to display in summaryPanel for checkboxes like SNP polymorphicStrainsdisable buttons
					//alert(childElts[j].id + '  -== ' + childElts[j].value);
					filterInfoOf[filterName] = [filterDisplayName, myFilterValues.join()];
				}
			break;
			
		    default: alert('Filterval-element type '+filterValueElt.type+' not handled at this time');
		    }		   		    
		}
	    }
	    break;
	default: continue;
	}
    }
    return filterInfoOf;
}

/*

=head2 expandListCompactSiblings()

Show full summary-tree list, while compacting its siblings. Used to indicate to
user which attribute tree is currently active in his query, even though he/she may
have attributes selected from other, inactive att-pages.

=cut

*/
function expandListCompactSiblings(listId) {
    targetListDiv = document.getElementById(listId);
    siblingDivs = targetListDiv.parentNode.childNodes; 
    //alert("Expanding alist "+listId+', compacting other attpage-lists');

    // Compact sibling divs
    var loop_length = siblingDivs.length; 
    for(var i=0; i < loop_length; i++ ) { 
    //for(otherListId in otherListIds) {
	if(siblingDivs[i].nodeName != 'DIV') continue; // get div only
	if(siblingDivs[i].id == listId) continue; // skip the target div itself
	subListDivs = siblingDivs[i].getElementsByTagName('div');
	//alert('Compacting list div, id='+siblingDivs[i].id+', with '+subListDivs.length+' items on it');

	// hide the div containing the list and show a note with the att-count in its stead
	var spans = siblingDivs[i].getElementsByTagName('span');
	if(spans.length > 1) { // delete this element if already exists
	    // alert('Removing existing count-note w/ innerHTML='+spans[1].innerHTML);
	    siblingDivs[i].removeChild(spans[1]);
	}
	// then recreate element w/ updated counts
        var subListDivCountNote = document.createElement("span");
	subListDivCountNote.className = 'mart_summarypanel_listitem_disabled';
	//subListDivCountNote.style.color = 'grey';
	subListDivCountNote.innerHTML = '['+subListDivs.length+' enabled]';
 	siblingDivs[i].insertBefore(subListDivCountNote, null); // add as last child

	// Hide the list of divs if necessary
	var loop_length_1 = subListDivs.length;
	for(j=0; j< loop_length_1; j++){
	    turnOff(subListDivs[j]); //.style.display = 'none';
	}
	// Finally set the whole listcontainer-div to disabled style (grey etc.)
	siblingDivs[i].className = 'mart_summarypanel_list_disabled';
	
	// TEMPORARY: hide entire list, control att-pages via radio buttons on mainpanel instead 
	turnOff(siblingDivs[i]);
    }

    // Delete the count-note IF there are any items on the list
    var subListDivs = targetListDiv.getElementsByTagName('div');
    var spans       = targetListDiv.getElementsByTagName('span');
    if(spans.length > 1 && subListDivs.length > 0) {
	//alert('Removing existing count-note w/ innerHTML='+spans[1].innerHTML);
	targetListDiv.removeChild(spans[1]);
    }

    // And finally (re)how the list items and set them to the original enabled-style
    targetListDiv.className = 'mart_summarypanel_list';
    for(j=0; j< subListDivs.length; j++){
	subListDivs[j].style.display = 'block';
    }

    targetListDiv.style.display = 'inline';
}

/*

=head2 setHighlightedSummaryPanelBranch()

Change the style of the element with this ID, to make it highlighted in the 
summary-tree. 

=cut

*/
function setHighlightedSummaryPanelBranch(eltId) {
    // un-highlight an existing element, if necessary
    var highlightedSummaryPanelBranchEltId = document.mainform['summarypanel__current_highlighted_branch'].value;
    var highlightedSummaryPanelBranchElt = document.getElementById(highlightedSummaryPanelBranchEltId);
    if(highlightedSummaryPanelBranchElt) {
    	//alert(highlightedSummaryPanelBranchElt);
		if(highlightedSummaryPanelBranchElt.className == 'mart_summarypanel_listheader_highlighted' )
		{	
			highlightedSummaryPanelBranchElt.className = 'mart_summarypanel_listheader';
			// and change the colour of count span
			if (highlightedSummaryPanelBranchElt.id != "show_linked_datasetpanel")
			{	highlightedSummaryPanelBranchElt.childNodes[1].className = 'mart_summarypanel_dataset_entrycount'; }
		}
		if(highlightedSummaryPanelBranchElt.className == 'mart_summarypanel_AttFiltHeader_highlighted' )
		{	highlightedSummaryPanelBranchElt.className = 'mart_summarypanel_AttFiltHeader'; }

		// Also change the colour of table cell which sets the background of the strip
		if (highlightedSummaryPanelBranchElt.parentNode.parentNode.parentNode.parentNode.className == 'mart_summarypanel_listheaderTable_highlighted')
		{	highlightedSummaryPanelBranchElt.parentNode.parentNode.parentNode.parentNode.className = 'mart_summarypanel_listheaderTable';	}
    }
	//alert('Setting summary panel branch '+eltId+' as the highlighted one');
    // Highlight this element
	if (eltId != "show_results")/// hack to avoid highlighting of results button. as it was crashing on IE
	{
    	var elt2highlight = document.getElementById(eltId);
		
		//alert('Setting summary panel branch '+elt2highlight+' as the highlighted one');
		if(elt2highlight.className == 'mart_summarypanel_listheader')
		{	
			elt2highlight.className = 'mart_summarypanel_listheader_highlighted'; 
			// and change the colour of count span 
			if (elt2highlight.id != "show_linked_datasetpanel")
			{ elt2highlight.childNodes[1].className = 'mart_summarypanel_dataset_entrycount_highlighted';	}
		}

		if(elt2highlight.className == 'mart_summarypanel_AttFiltHeader')
		{	elt2highlight.className = 'mart_summarypanel_AttFiltHeader_highlighted'; 	}

		// Also change the colour of table cell which sets the background of the strip
		if (elt2highlight.parentNode.parentNode.parentNode.parentNode.className == 'mart_summarypanel_listheaderTable')
		{	elt2highlight.parentNode.parentNode.parentNode.parentNode.className = 'mart_summarypanel_listheaderTable_highlighted';	}
		
		// set session variable accordingly
		document.mainform['summarypanel__current_highlighted_branch'].value = eltId;
		//alert('dear');
	}	
}

/*

=head2 getElements()

Recursively find all child elements of the given element and return as list.

=cut

*/
function getElements(elt) {
    var descElts = [];
    var loop_length = elt.childNodes.length;
    for(var i=0;i < loop_length;i++) {
	// only get element-nodes, not attribute-nodes
	if(elt.childNodes[i].nodeType != 1) continue;

	//alert('Got elt-type childnode '+elt.childNodes[i]+', adding to list & getting grandchildren');
	descElts.push(elt.childNodes[i]);
	// Only get grandchildren if they're not inside select-menus or whatever
	if(elt.childNodes[i].type != 'select-one'
	   && elt.childNodes[i].type != 'select-multiple') {
	    var grandChildNodes = getElements(elt.childNodes[i]);
	    //alert('Got grandchildnodes list of length='+grandChildNodes.length);
	    if(grandChildNodes.length > 0) {
		descElts = descElts.concat(grandChildNodes);
	    }
	}
    }
    return descElts;
}
/*

=head2 filterEltHasValue()

Figure out if user has supplied an actual value by now. Gotta do this differently
depending on filtervalue element type (textfield, select-list menus, etc).

=cut

*/
function filterEltHasValue(filterValueElt) {
    var filterIsEnabled = false;
    switch(filterValueElt.type) {
    case 'text':
	if(filterValueElt.value != '') {
	    filterIsEnabled = true;
	}
	break;
    case 'select-one':
	if(filterValueElt.selectedIndex >= 0) {
	    filterIsEnabled = true;
	    //alert('select-single menu '+filterValueElt.name+' has a value(s) ('+filterValueElt.options[filterValueElt.selectedIndex].value+'), so gotta enable parent filtercollection ' + filterCollectionCheckboxName);
	}
	break;
    case 'select-multiple':
	if(filterValueElt.selectedIndex >= 0) {
	    filterIsEnabled = true;
	     //alert('select-multiple menu '+filterValueElt.name+' has a value(s) ('+filterValueElt.options[filterValueElt.selectedIndex].value+'), so gotta enable parent filtercollection ' + filterCollectionCheckboxName);
	}
	break;
    case 'radio':
	//alert('doing radio-button '+filterValueElt.name+', value='+filterValueElt.value+', checked='+filterValueElt.checked);
	// Radio button lists always have one option selected, so they're always on
	filterIsEnabled = true;
	break;
    case 'file':
	//alert('doing file-upload button '+filterValueElt.name+', value='+filterValueElt.value);
	// Check if there's a filepath present here
	if(filterValueElt.value) {
	    filterIsEnabled = true;
	}
	break;
    case 'textarea':
	//alert('doing textarea '+filterValueElt.name+', value='+filterValueElt.value);
	// ? how to handle this
	if(filterValueElt.value) {
	    filterIsEnabled = true;
	}
	break;
    default: alert('Odd, form element type '+filterValueElt.type+' not handled properly at this time');      
    }
    return filterIsEnabled;
}

/*

=head2 checkFilterCollectionCheckbox()

Function to check the filtercollection-checkbox if a filter input element is changed by userf
and a non-empty value selected. Just convenient to not have to check checkbox by hand :P
Calling this method has the nice side-effect that all filters in the collection are updated
(if they have any valid values).

=cut

*/
function checkFilterCollectionCheckbox(filterCollectionCheckboxName ) {
    var checkboxElt = document.mainform.elements[filterCollectionCheckboxName];
    //alert('Checking checkbox '+filterCollectionCheckboxName);
    if(!checkboxElt.checked) {
	checkboxElt.checked = 'checked'; // check the box if it's not checked already
    }
    checkboxElt.onchange();     // start the onchange cascade and enable filters within
}

/*

=head2 highlightPanelSection()

Function to unhide (if necessary) and highlight a filter or attribute section on the main
Mart panel. Called when user clicks on a filter or attribute name on the left menubar. If
the grandparent filtergroup section is collapsed, it will be expanded.

=cut

*/
var highlightedPanelSectionElt; // global variable to  keep track of currently highlighted section
var highlightedPanelSectionWasHidden; // global variable to  keep track of  visible-status of 
                                      // highlighted section, in case it needs to be re-hidden
function highlightPanelSection(sectionId) {
    //alert('Highlighting section id='+sectionId);
    if(highlightedPanelSectionElt) {
	// Un-highlight the currently highlighted element, before doing this one
	highlightedPanelSectionElt.style.border = "none";
	
	// Also re-hide its container section if it had to be un-hidden before
	if(highlightedPanelSectionWasHidden) {
	    visibility(highlightedPanelSectionElt.parentNode.parentNode.id, 'hide');
	}
    }
    var elt2highlight = document.getElementById(sectionId); // actual section to highlight
    // If grandparent filtergroup or attributegroup section is currently hidden, unhide it
    var grandparent_node = elt2highlight.parentNode.parentNode;
    highlightedPanelSectionWasHidden = false;
    //alert('grandparent node of elt2highlight '+sectionId+' is '+grandparent_node.id+', display state='+grandparent_node.style.display+',class='+grandparent_node.className);
    if(grandparent_node.style.display == "none") {
	//alert('Grandparent node '+grandparent_node.id+' of '+elt2highlight.id+' is hidden, gotta unhide it via visibility()');
	visibility(grandparent_node.id, 'show');
	highlightedPanelSectionWasHidden = true;
    }
    
    elt2highlight.style.border = "2px yellow solid";
    //alert('Highlighting section w/ id='+elt2highlight.id+',style='+elt2highlight.style+',className='+elt2highlight.className+', bgcolor='+elt2highlight.style.backgroundColor);
    highlightedPanelSectionElt = elt2highlight;
    
    // NOTE TO SELF: is it possible to scroll the browser window so section is visible?
    
    return true;
}

/*

=head2 visibility()

Functions to toggle show/hide collapsible page sections. Borrowed mostly from toggle.js
which comes with the Generic Genome Browser package, after stripping out cookie-stuff.
When plus-button is clicked the corresponding section is made visible, plus-button
is hidden and minus-button made visible. Vice versa when minus-button is clicked.

=cut

*/
function visibility(elt_name, state) {
    // Get actual element to collapse or expand
    var element = document.getElementById(elt_name);

    // Get elements containing the collapse/expand control buttons
    var show_control = document.getElementById(elt_name + "__show");
    var hide_control = document.getElementById(elt_name + "__hide");
    
    // Show or hide all three of the above
    if (state == "show") {
	turnOn(element);
	turnOff(show_control);
	turnOn(hide_control);
    } else if (state == "hide"){
	turnOff(element);
	turnOff(hide_control);
	turnOn(show_control);
    }
    // Lastly store the state-flag in a hidden parameter, if there is one
    var state_param = document.mainform.elements[elt_name+'__visibility'];
    if(state_param) {
	state_param.value = state;
    }
}

/*

=head2 turnOn()

Show a previously hidden element.

=cut

*/
function turnOn (a) {
    if(!a) return false;
    a.style.display="block";
}

/*

=head2 turnOff()

Hide a previously visible element.

=cut

*/
function turnOff (a) {
    if(!a) return false;
    a.style.display="none";
}

/*

=head2 setVisibleStatus()

Set all elements of a certain CSS class to a hidden state.

=cut

*/
function setVisibleStatus() {
    var spans=document.getElementsByTagName("div");
    for (var i=0; i < spans.length; i++){
	if (spans[i].className=="ctl_hidden" || spans[i].className=="el_hidden" ) {
	    spans[i].style.display = "none";
	}
    }
    
    //alert('FROM ONLOAD OF BODY: SETVISIBLE STATUS');
}

/*

=head2 checkCheckboxesInContainer()

Check/uncheck all checkboxes in a given container. Used to select or deselect all
attributes in a collection, so it's attached to two checkbox controllers.

=cut

*/
function checkCheckboxesInContainer(elt,state) {
    //var containerId = elt.id.replace(/_[an]$/,"");
    //alert("Setting all checkboxes in container "+elt.parentNode.id+',obj='+elt.parentNode+' to state '+state);
    var container = elt.parentNode;
    if (!container) { return false; }
    var checkboxes = container.getElementsByTagName('input');
    if (!checkboxes) { return false; }
    var loop_length = checkboxes.length;
    for (var i=0; i<loop_length; i++) {
	if (checkboxes[i].type == 'checkbox') {
	    //alert("Got checkbox w/ name="+checkboxes[i].name+', id='+checkboxes[i].id);
	    // First check or uncheck the actual checkbox, but only IF necessary! don't bother
	    // doing that if box is already in the desired state (messed with some things)
	    if(checkboxes[i].checked == state){ continue; }
	    checkboxes[i].checked=state;
	    if(checkboxes[i].onchange) { checkboxes[i].onchange(); }
	    
	    // then check if there's a non-checkbox parameter associated with this
	    // checkbox which should be turned on or off as well
	    var other_param_name = checkboxes[i].name.replace(/\__checkbox$/,"");
	    var other_param = document.mainform.elements[other_param_name];
	    if (other_param) {
		if(state) {
		    other_param.value = 'on';
		}
		else {
		    other_param.value = 'off';
		}
	    }
	}
    }
    // Uncheck of both select/deselect all controllers
    //alert('Unchecking both controller checkboxes id='+elt.parentNode.id+'_[an]');
    check(elt.parentNode.id+"_a", 0);
    check(elt.parentNode.id+"_n", 0);

    // Then check only this controller checkbox (could be the _n or the _a one)
    elt.checked = "checked";
    return false;
}

/*

=head2 check()

Checks or unchecks a checkbox with the ID provided.

=cut

*/
function check(eltId, state) {
    var checkboxElt = document.getElementById(eltId);
    if(checkboxElt && checkboxElt.type == 'checkbox') {
	//alert('setting checkbox '+checkboxElt.name+' to state '+state);
	if(!state) {
	    checkboxElt.checked = false;
	}
	else {
	    checkboxElt.checked = 'checked';
	}
    }
}

/*
=head2 checkAttributeCheckbox()
  	 
  	 Function to check the attribute-checkbox if an attribute filter input element is changed by user
  	 and a non-empty value selected. Just convenient to not have to check checkbox by hand :P
  	 Calling this method has the nice side-effect that all filters in the collection are updated
  	 (if they have any valid values).
  	 
=cut
  	 
*/
  	 function checkAttributeCheckbox(attributeCheckboxName ) {
  	     var checkboxElt = document.mainform.elements[attributeCheckboxName];
  	     //alert('Checking checkbox '+attributeCheckboxName);
  	     if(!checkboxElt.checked) {
  	         checkboxElt.checked = 'checked'; // check the box if it's not checked already
  	     }
  	     checkboxElt.onchange();     // start the onchange cascade and enable attributefilters within
  	 }


/*
=head2 detectBrowserProperties()
  	 
	retruns the browser type, version and OS  	 
=cut
  	
*/
function detectBrowserProperties()
{
	var BrowserDetect = {
	init: function () {
		this.browser = this.searchString(this.dataBrowser) || "An unknown browser";
		this.version = this.searchVersion(navigator.userAgent)
			|| this.searchVersion(navigator.appVersion)
			|| "an unknown version";
		this.OS = this.searchString(this.dataOS) || "an unknown OS";
	},
	searchString: function (data) {
		for (var i=0;i<data.length;i++)	{
			var dataString = data[i].string;
			var dataProp = data[i].prop;
			this.versionSearchString = data[i].versionSearch || data[i].identity;
			if (dataString) {
				if (dataString.indexOf(data[i].subString) != -1)
					return data[i].identity;
			}
			else if (dataProp)
				return data[i].identity;
		}
	},
	searchVersion: function (dataString) {
		var index = dataString.indexOf(this.versionSearchString);
		if (index == -1) return;
		return parseFloat(dataString.substring(index+this.versionSearchString.length+1));
	},
	dataBrowser: [
		{
			string: navigator.vendor,
			subString: "Apple",
			identity: "Safari"
		},
		{
			prop: window.opera,
			identity: "Opera"
		},
		{
			string: navigator.vendor,
			subString: "iCab",
			identity: "iCab"
		},
		{
			string: navigator.vendor,
			subString: "KDE",
			identity: "Konqueror"
		},
		{
			string: navigator.userAgent,
			subString: "Firefox",
			identity: "Firefox"
		},
		{	// for newer Netscapes (6+)
			string: navigator.userAgent,
			subString: "Netscape",
			identity: "Netscape"
		},
		{
			string: navigator.userAgent,
			subString: "MSIE",
			identity: "Explorer",
			versionSearch: "MSIE"
		},
		{
			string: navigator.userAgent,
			subString: "Gecko",
			identity: "Mozilla",
			versionSearch: "rv"
		},
		{ 	// for older Netscapes (4-)
			string: navigator.userAgent,
			subString: "Mozilla",
			identity: "Netscape",
			versionSearch: "Mozilla"
		}
	],
	dataOS : [
		{
			string: navigator.platform,
			subString: "Win",
			identity: "Windows"
		},
		{
			string: navigator.platform,
			subString: "Mac",
			identity: "Mac"
		},
		{
			string: navigator.platform,
			subString: "Linux",
			identity: "Linux"
		}
	]

	};
	BrowserDetect.init();
	
	var propertiesArr = new Array();
	propertiesArr[0] = BrowserDetect.browser;
	propertiesArr[1] = BrowserDetect.version;
	propertiesArr[2] = BrowserDetect.OS;
	
	return propertiesArr;
}


/*
=head2 updateDependentAttributes()
  	 
  	 updates (disabled/enabled) attributes.
=cut
  	
*/
var dependencyMap = new Array();
var dependencyType = new Array();
var dependencyFilterMap = new Array();
function updateDependentAttributes(parname) {
 // For each dependency for dependent in the dependencyMap,
 // check for selection. 
 var requiredDepsChecked = 0;
 var depMapEntry = dependencyMap[parname];
 for (var i = 0; i < depMapEntry.length; i++) {
 	var dep = depMapEntry[i];
 	var depCheck = document.mainform.elements[dep];
 	if (depCheck && depCheck.checked) {
 		requiredDepsChecked++;
		if (dependencyType[parname]!='all') break; // Time-saver.
	}
 }
 
 // ANY: If any selected, enable the dependent.
 // ALL: If all selected, enable the dependent.
 // ANY/ALL: If none selected, disable the dependent.
 // NONE: If none selected, enable the dependent.
 
 if ((requiredDepsChecked>0 && dependencyType[parname]=='any')
    ||(requiredDepsChecked==depMapEntry.length && dependencyType[parname]=='all')
    ||(requiredDepsChecked==0 && dependencyType[parname]=='none')) {
 	// Enable.
   	var depFiltMapEntry = dependencyFilterMap[parname];
   	if (depFiltMapEntry) {
   		document.mainform.elements[depFiltMapEntry].disabled = false; 
   	}
   	document.mainform.elements[parname].disabled = false; 
 } else {
 	// Disable.
   	var depFiltMapEntry = dependencyFilterMap[parname];
   	if (depFiltMapEntry) {
   		document.mainform.elements[depFiltMapEntry].disabled = true;
   		document.mainform.elements[depFiltMapEntry].value = '';  
   	}
  	document.mainform.elements[parname].checked = false; 
   	document.mainform.elements[parname].disabled = true; 
   	document.mainform.elements[parname].onchange(); 
 } 
}
/*

=head1 CVSINFO

$Id$ 

=cut

*/
