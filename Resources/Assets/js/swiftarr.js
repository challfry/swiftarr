import("/js/bootstrap.bundle.js");

// Make the like/love/laugh buttons post their actions when tapped.
for (let btn of document.querySelectorAll('[data-action]')) {
	let action = btn.dataset.action;
	if (action == "deletePost" || action == "deleteTwarrt" || action == "deleteForum") {
		btn.addEventListener("click", deleteAction);
	}
	else if (action == "laugh" || action == "like" || action == "love") {
		btn.addEventListener("click", likeAction);
	}
	else if (action == "follow") {
		btn.addEventListener("click", followEventAction);
	}
	else if (action == "filterfollowing") {
		btn.addEventListener("click", filterFollowingEventAction);
	}
	else if (action == "filterEventType") {
		btn.addEventListener("click", eventFilterDropdownTappedAction);
	}
}

function likeAction() {
	let postid = event.target.closest('[data-postid]').dataset.postid;
	let tappedButton = event.target;
	let listType = event.currentTarget.closest('ul')?.dataset.listtype;
	var path =  '/' + listType + '/' + postid + '/';

	if (!tappedButton.checked) {
		path = path + "unreact";
	}
	else {
		path = path + tappedButton.dataset.action;
	}
		
	let buttons = tappedButton.closest('[data-state]').querySelectorAll("input");
	setLikeButtonsState(buttons, tappedButton, false);

	let req = new Request(path, { method: 'POST' });
	fetch(req).then(function(response) {
		let postElement = tappedButton.closest('[data-postid]');
		let errorDiv = tappedButton.closest('[data-postid]').querySelector('[data-purpose="errordisplay"]');
		if (response.ok) {
			errorDiv.textContent = "";
		}
		else {
			errorDiv.textContent = "Could not post reaction";
		}
		setTimeout(() => {
			setLikeButtonsState(buttons, tappedButton, true);
			updateLikeCounts(postElement);
		}, 1000)
	}).catch(error => {
		tappedButton.closest('[data-postid]').querySelector('[data-purpose="errordisplay"]').textContent = "Could not post reaction";
		setLikeButtonsState(buttons, tappedButton, true);
	});
}

function setLikeButtonsState(buttons, tappedButton, state) {
	let spinnerElem = tappedButton.labels[0]?.querySelector(".spinner-border");
	if (state) {
		for (let btn of buttons) {
			btn.disabled = false;
		}
		if (spinnerElem !== null) spinnerElem.classList.add("d-none");
	}
	else {
		for (let btn of buttons) {
			btn.disabled = true;
			if (btn.checked && btn != tappedButton) {
				btn.checked = false;
			}
		}
		if (spinnerElem !== null) spinnerElem.classList.remove("d-none");
	}
}

function followEventAction() {
	let eventid = event.target.closest('[data-eventid]').dataset.eventid;
	let tappedButton = event.target;
	let actionStr = tappedButton.checked ? 'POST' : 'DELETE';
	let req = new Request('/events/' + eventid + '/favorite', { method: actionStr });
	let spinnerElem = tappedButton.labels[0]?.querySelector(".spinner-border");
	if (spinnerElem !== null) spinnerElem.classList.remove("d-none");
	let errorDiv = tappedButton.closest('[data-eventid]').querySelector('[data-purpose="errordisplay"]');
	fetch(req).then(function(response) {
		if (response.ok) {
			errorDiv.innerHTML = "";
			tappedButton.closest('[data-eventfavorite]').dataset.eventfavorite = tappedButton.checked ? "true": "false";
		}
		else {
			response.json().then( data => {
				errorDiv.innerHTML = "<b>Error:</b> " + data.reason
			});
		}
		setTimeout(() => {
			if (spinnerElem !== null) spinnerElem.classList.add("d-none");
		}, 1000);
	}).catch(error => {
		if (spinnerElem !== null) spinnerElem.classList.add("d-none");
		errorDiv.innerHTML = "<b>Error:</b> " + error;
	});
}

document.getElementById('deleteModal')?.addEventListener('show.bs.modal', function(event) {
	let postElem = event.relatedTarget.closest('[data-postid]');
	let deleteBtn = event.target.querySelector('[data-delete-postid]');
	deleteBtn.setAttribute('data-delete-postid', postElem.dataset.postid);
	event.target.querySelector('[data-purpose="errordisplay"]').innerHTML = ""
})

function deleteAction() {
	let postid = event.target.dataset.deletePostid;
	let modal = event.target.closest('.modal');
	let path = "";
	let action = event.target.dataset.action
	if (action == "deleteTwarrt") {
		path = "/tweets/" + postid + "/delete";
	}
	else if (action == "deleteForum")
		path = "/forum/" + postid + "/delete";
	else {
		path = "/forumpost/" + postid + "/delete";
	}
	let req = new Request(path, { method: 'POST' });
	fetch(req).then(response => {
		if (response.status < 300) {
			bootstrap.Modal.getInstance(modal).hide()
			let deletedPost = document.querySelector('li[data-postid="' + postid + '"]');
			if (deletedPost != null) {
				deletedPost.remove()
			}
			else {
				location.reload();
			}	
		}
		else {
			response.json().then( data => {
				modal.querySelector('[data-purpose="errordisplay"]').innerHTML = "<b>Error:</b> " + data.reason
			})
		}
	})
}

// Make every post expand when first clicked, showing the previously hidden action bar.
for (let posElement of document.querySelectorAll('.has-action-bar')) {
	posElement.addEventListener("click", showActionBar);
}
for (let posElement of document.querySelectorAll('.has-action-bar')) {
	posElement.addEventListener("click", showActionBar);
}
function showActionBar() {
	let actionBar = event.currentTarget.querySelector('[data-label="actionbar"]');
	if (!actionBar.classList.contains("show")) {
		var bsCollapse = new bootstrap.Collapse(actionBar, { toggle: false }).show();
		updateLikeCounts(event.currentTarget);
	}
}
function updateLikeCounts(postElement) {
	let listType = postElement.closest('ul')?.dataset.listtype;
	let postid = postElement.dataset.postid;
	if (!listType || !postid) return;
	fetch("/" + listType + "/" + postid)
		.then(response => response.json())
		.then(jsonStruct => {
			let actionBar = postElement.querySelector('[data-label="actionbar"]');
			if (jsonStruct.laughs) { 
				let laughspan = actionBar.querySelector('.laughtext');
				if (laughspan) {
					laughspan.textContent = (jsonStruct.laughs.length > 0 ? jsonStruct.laughs.length : "");
				}
			}
			if (jsonStruct.likes) { 
				let likespan = actionBar.querySelector('.liketext');
				if (likespan) {
					likespan.textContent = (jsonStruct.likes.length > 0 ? jsonStruct.likes.length : "");
				}
			}
			if (jsonStruct.loves) { 
				let lovespan = actionBar.querySelector('.lovetext');
				if (lovespan) {
					lovespan.textContent = (jsonStruct.loves.length > 0 ? jsonStruct.loves.length : "");
				}
			}
		});
}


// MARK: - messagePostForm Handlers
for (let input of document.querySelectorAll('.image-upload-input')) {
	updatePhotoCardState(input.closest('.card'));
	input.addEventListener("change", function() { updatePhotoCardState(event.target.closest('.card')); })
}
function updatePhotoCardState(cardElement) {
	let imgElem = cardElement.querySelector('img');
	let imgContainer = cardElement.querySelector('.img-for-upload-container');
	let noImgElem = cardElement.querySelector('.no-image-marker');
	let fileInputElem = cardElement.querySelector('.image-upload-input');
	let hiddenFormElem = cardElement.querySelector('input[type="hidden"]');
	let imageSwapButton = cardElement.querySelector('.twitarr-image-swap');
	let imageRemoveButton = cardElement.querySelector('.twitarr-image-remove');
	let imageVisible = true;
	if (fileInputElem.files.length > 0) {
		imgElem.src = window.URL.createObjectURL(fileInputElem.files[0]);
		imgContainer.style.display = "block";
		noImgElem.style.display = "none";
		hiddenFormElem.value = "";
	}
	else if (hiddenFormElem.value) {
		imgElem.src = "/api/v3/image/thumb/" + hiddenFormElem.value;
		imgContainer.style.display = "block";
		noImgElem.style.display = "none";
	}
	else {
		imgContainer.style.display = "none";
		noImgElem.style.display = "block";
		imageRemoveButton.disabled = true
		imageVisible = false;
	}
	if (imageSwapButton) {
		imageSwapButton.disabled = !imageVisible;
	}
	imageRemoveButton.disabled = !imageVisible;
	let nextCard = cardElement.nextElementSibling;
	if (nextCard != null) {
		nextCard.style.display = imgContainer.style.display;
	}
}

for (let btn of document.querySelectorAll('.twitarr-image-remove')) {
	btn.addEventListener("click", removeUploadImage);
}
function removeUploadImage() {
	let cardElement = event.target.closest('.card');
	let nextCard = cardElement;
	while (nextCard = cardElement.nextElementSibling) {
		cardElement.querySelector('.image-upload-input').files = nextCard.querySelector('.image-upload-input').files;
		cardElement.querySelector('input[type="hidden"]').value = nextCard.querySelector('input[type="hidden"]').value;
		updatePhotoCardState(cardElement);
		cardElement = nextCard;
	}
	let lastCard = cardElement.parentElement.lastElementChild;
	lastCard.querySelector('.image-upload-input').value = null
	lastCard.querySelector('input[type="hidden"]').value = "";
	updatePhotoCardState(lastCard);
}

for (let btn of document.querySelectorAll('.twitarr-image-swap')) {
	btn.addEventListener("click", swapUploadImage);
}
function swapUploadImage() {
	let cardElement = event.target.closest('.card');
	let prevCard = cardElement.previousElementSibling;
	let curFiles = cardElement.querySelector('.image-upload-input').files;
	let curServerFile = cardElement.querySelector('input[type="hidden"]').value
	cardElement.querySelector('.image-upload-input').files = prevCard.querySelector('.image-upload-input').files;
	cardElement.querySelector('input[type="hidden"]').value = prevCard.querySelector('input[type="hidden"]').value;
	prevCard.querySelector('.image-upload-input').files = curFiles;
	prevCard.querySelector('input[type="hidden"]').value = curServerFile;
	updatePhotoCardState(prevCard);
	updatePhotoCardState(cardElement);
}

// For all form submits that display an error alert on fail but load a new page on success.
for (let form of document.querySelectorAll('form.ajax')) {
	form.addEventListener("submit", function(event) { submitAJAXForm(form, event); });
}
function submitAJAXForm(formElement, event) {
    event.preventDefault();
	var req = new XMLHttpRequest();
	req.onload = function() {
		if (this.status < 300) {
			let successURL = formElement.dataset.successurl;
			if (successURL) {
				location.assign(successURL);
			}
			else {
				location.reload();
			}
		}
		else {
			var data = JSON.parse(this.responseText);
			let alertElement = formElement.querySelector('.alert');
			alertElement.innerHTML = "<b>Error:</b> " + data.reason;
			alertElement.classList.remove("d-none")
		}
	}
	req.onerror = function() {
		let alertElement = formElement.querySelector('.alert');
		alertElement.innerHTML = "<b>Error:</b> " + this.statusText;
		alertElement.classList.remove("d-none")
	}
	req.open("post", formElement.action);
    req.send(new FormData(formElement));
}


// Populates username completions for a partial username. 
let userSearchAPICallTimeout = null;
let userSearch = document.querySelector('input.user-autocomplete');
userSearch?.addEventListener('input', function(event) {
	if (userSearchAPICallTimeout) {
		clearTimeout(userSearchAPICallTimeout);
	}
	userSearchAPICallTimeout = setTimeout(() => {
		userSearchAPICallTimeout = null;
		let searchString = userSearch.value?.replace(/\s+/g, '');
		if (searchString.length < 2) { return }
		fetch("/seamail/usernames/search/" + encodeURIComponent(searchString))
			.then(response => response.json())
			.then(userHeaders => {
				let suggestionDiv = document.getElementById('name_suggestions');
				suggestionDiv.innerHTML = "";
				for (user of userHeaders) {
					let nameDiv = document.createElement("div");
					nameDiv.classList.add("col-auto", "border");
					nameDiv.dataset.uuid = user.userID;
					nameDiv.appendChild(document.createTextNode("@" + user.username));
					suggestionDiv.append(nameDiv);
					nameDiv.addEventListener('click', function(event) {
						let participantsDiv = document.getElementById('named_participants');
						for (index = 0; index < participantsDiv.children.length; ++index) {
							if (participantsDiv.children[index].dataset['uuid'] == nameDiv.dataset.uuid) {
								return;
							}
						} 
						let divCopy = nameDiv.cloneNode(true);
						participantsDiv.append(divCopy);
						divCopy.addEventListener('click', function(event) {
							divCopy.remove();
						});
						let names = [];
						for (index = 1; index < participantsDiv.children.length; ++index) {
							names.push(participantsDiv.children[index].dataset['uuid']);
						} 
						let hiddenFormElem = document.getElementById('participants_hidden');
						hiddenFormElem.value = names;
					});
				}
			})
		
	}, 200);
})

// MARK: - Schedule Page Handlers

function filterFollowingEventAction() {
	let category = document.getElementById("eventFilterMenu").dataset.category;
	let followingOnly = document.getElementById("eventFollowingFilter").classList.contains("active");
	filterEvents(category, followingOnly);
}

function eventFilterDropdownTappedAction() {
	let categoryButton = document.getElementById("eventFilterMenu");
	let followingButton = document.getElementById("eventFollowingFilter");
	let category = event.target.dataset.category;
	categoryButton.innerHTML = event.target.innerHTML;
	categoryButton.dataset.category = category;
	for (menuItem of categoryButton.parentElement.querySelectorAll('[data-action]')) {
		menuItem.classList.remove("active");
	}
	event.target.classList.add("active");
	filterEvents(category, followingButton.classList.contains("active"));
}

function filterEvents(category, onlyFollowing) {
	for (let listItem of document.querySelectorAll('[data-eventid]')) {
		let hideEvent = (onlyFollowing && listItem.dataset.eventfavorite == "false") ||
				(category && category != "all" && category != listItem.dataset.eventcategory);
		if (hideEvent && listItem.classList.contains("show")) {
//			listItem.classList.remove("show")
			new bootstrap.Collapse(listItem)
		}
		else if (!hideEvent && !listItem.classList.contains("show")) {
//			listItem.classList.add("show")
			new bootstrap.Collapse(listItem)
		}
	}
}
